using System.Collections.Concurrent;
using System.Text.Json;
using GroupRide.Api.Hubs;
using GroupRide.Cohesion;
using GroupRide.Domain.Entities;
using GroupRide.Domain.Enums;
using GroupRide.Domain.Interfaces;
using GroupRide.Infrastructure.Data;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace GroupRide.Api.Services;

/// <summary>
/// Simulator demo: moves all riders along the ride route, broadcasts live positions, then completes the ride.
/// </summary>
public sealed class DemoRideSimulator
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly IHubContext<RideHub> _hub;
    private readonly ILogger<DemoRideSimulator> _logger;
    private readonly ConcurrentDictionary<Guid, CancellationTokenSource> _running = new();

    public DemoRideSimulator(
        IServiceScopeFactory scopeFactory,
        IHubContext<RideHub> hub,
        ILogger<DemoRideSimulator> logger)
    {
        _scopeFactory = scopeFactory;
        _hub = hub;
        _logger = logger;
    }

    public bool IsRunning(Guid rideId) => _running.ContainsKey(rideId);

    public async Task StartAsync(Guid rideId, Guid leaderUserId, CancellationToken ct = default)
    {
        var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        if (!_running.TryAdd(rideId, cts))
            throw new InvalidOperationException("A demo is already running for this ride.");

        try
        {
            await PrepareAsync(rideId, leaderUserId, cts.Token);
        }
        catch
        {
            _running.TryRemove(rideId, out _);
            cts.Dispose();
            throw;
        }

        _ = Task.Run(() => RunAsync(rideId, cts), CancellationToken.None);
    }

    private async Task PrepareAsync(Guid rideId, Guid leaderUserId, CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var ride = await db.Rides
            .Include(r => r.Members).ThenInclude(m => m.User)
            .Include(r => r.Stops)
            .FirstOrDefaultAsync(r => r.Id == rideId, ct)
            ?? throw new InvalidOperationException("Ride not found");

        if (ride.Members.All(m => m.UserId != leaderUserId || m.Role != RideRole.Leader))
            throw new UnauthorizedAccessException("Only the leader can start a demo.");

        if (ride.Status is RideStatus.Completed or RideStatus.Cancelled)
            throw new InvalidOperationException("Ride already finished.");

        if (ride.Status != RideStatus.Live)
        {
            ride.Status = RideStatus.Live;
            ride.StartedAt ??= DateTime.UtcNow;
        }

        // Ensure a small pack of riders so the live map is interesting in the simulator.
        await EnsureDemoRidersAsync(db, ride, ct);

        var path = BuildPath(ride);
        foreach (var m in ride.Members)
        {
            m.LastLat = path[0].Lat;
            m.LastLng = path[0].Lng;
            m.LastLocationAt = DateTime.UtcNow;
            m.Status = RiderStatus.Riding;
            m.Attended = true;
        }

        await db.SaveChangesAsync(ct);
        await BroadcastLocationsAsync(rideId, db);
        await _hub.Clients.Group($"ride:{rideId}").SendAsync("RideStateChanged", new { rideId, status = "Live" }, ct);
    }

    private async Task RunAsync(Guid rideId, CancellationTokenSource cts)
    {
        try
        {
            const int steps = 24;
            for (var step = 1; step <= steps; step++)
            {
                cts.Token.ThrowIfCancellationRequested();
                using var scope = _scopeFactory.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var locations = scope.ServiceProvider.GetRequiredService<ILocationStore>();

                var ride = await db.Rides
                    .Include(r => r.Members).ThenInclude(m => m.User)
                    .Include(r => r.Stops)
                    .FirstAsync(r => r.Id == rideId, cts.Token);

                if (ride.Status != RideStatus.Live)
                    break;

                var path = BuildPath(ride);
                var progress = step / (double)steps;
                var ts = DateTime.UtcNow;

                var ordered = ride.Members
                    .OrderBy(m => m.Role == RideRole.Leader ? 0 : m.Role == RideRole.Sweep ? 2 : 1)
                    .ToList();

                for (var i = 0; i < ordered.Count; i++)
                {
                    // Stagger pack: leader ahead, sweep behind.
                    var offset = Math.Clamp(progress - i * 0.03, 0, 1);
                    var point = PointAt(path, offset);
                    var member = ordered[i];
                    member.LastLat = point.Lat;
                    member.LastLng = point.Lng;
                    member.LastSpeedMps = 18 + (i == 0 ? 2 : 0);
                    member.LastHeading = 270;
                    member.LastLocationAt = ts;
                    member.Status = RiderStatus.Riding;
                    member.DistanceSinceStartKm = offset * ApproximateKm(path);
                    member.Attended = true;

                    var ping = new LocationPingRecord(
                        rideId, member.UserId, point.Lat, point.Lng, member.LastSpeedMps, member.LastHeading, 8, ts);
                    await locations.WriteAsync(ping, cts.Token);
                    db.LocationPings.Add(new LocationPing
                    {
                        RideId = rideId,
                        UserId = member.UserId,
                        Lat = point.Lat,
                        Lng = point.Lng,
                        SpeedMps = member.LastSpeedMps,
                        Heading = member.LastHeading,
                        AccuracyMeters = 8,
                        Timestamp = ts
                    });
                }

                await db.SaveChangesAsync(cts.Token);
                await BroadcastLocationsAsync(rideId, db);

                await Task.Delay(TimeSpan.FromMilliseconds(1200), cts.Token);
            }

            // Complete the ride
            using (var scope = _scopeFactory.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var tracker = scope.ServiceProvider.GetRequiredService<CohesionStateTracker>();
                var ride = await db.Rides
                    .Include(r => r.Members).ThenInclude(m => m.User)
                    .Include(r => r.Stops)
                    .Include(r => r.Timeline)
                    .FirstAsync(r => r.Id == rideId);

                if (ride.Status == RideStatus.Live)
                {
                    var path = BuildPath(ride);
                    ride.Status = RideStatus.Completed;
                    ride.CompletedAt = DateTime.UtcNow;
                    foreach (var m in ride.Members)
                    {
                        m.LastLat = path[^1].Lat;
                        m.LastLng = path[^1].Lng;
                        m.LastLocationAt = DateTime.UtcNow;
                        m.Attended = true;
                    }

                    if (ride.Timeline is null)
                    {
                        var started = ride.StartedAt ?? ride.CompletedAt.Value.AddMinutes(-15);
                        var minutes = Math.Max(1, (ride.CompletedAt.Value - started).TotalMinutes);
                        ride.Timeline = new RideTimeline
                        {
                            RideId = ride.Id,
                            DistanceKm = Math.Round(ApproximateKm(path), 1),
                            DurationMinutes = Math.Round(minutes, 1),
                            RoutePolyline = ride.RoutePolyline,
                            StopsJson = JsonSerializer.Serialize(ride.Stops.Select(s => new { s.Name, s.Kind, s.Lat, s.Lng })),
                            AttendanceJson = JsonSerializer.Serialize(ride.Members.Select(m => new
                            {
                                m.UserId,
                                m.User.DisplayName,
                                Attended = true
                            })),
                            CreatedAt = DateTime.UtcNow
                        };
                    }

                    tracker.Clear(rideId);
                    await db.SaveChangesAsync();
                    await BroadcastLocationsAsync(rideId, db);
                    await _hub.Clients.Group($"ride:{rideId}").SendAsync("RideCompleted", new { rideId });
                    await _hub.Clients.Group($"ride:{rideId}").SendAsync("RideStateChanged", new { rideId, status = "Completed" });
                }
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogInformation("Demo cancelled for ride {RideId}", rideId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Demo failed for ride {RideId}", rideId);
        }
        finally
        {
            if (_running.TryRemove(rideId, out var existing))
                existing.Dispose();
        }
    }

    private async Task EnsureDemoRidersAsync(AppDbContext db, Ride ride, CancellationToken ct)
    {
        var needed = Math.Max(0, 3 - ride.Members.Count);
        if (needed == 0) return;

        var roster = new[]
        {
            ("Alex Rivera", RideRole.Rider),
            ("Sam Chen", RideRole.Sweep),
            ("Jordan Lee", RideRole.Rider)
        };

        var added = 0;
        foreach (var (name, role) in roster)
        {
            if (added >= needed) break;
            if (role == RideRole.Sweep && ride.Members.Any(m => m.Role == RideRole.Sweep))
                continue;

            var email = $"demo-{Guid.NewGuid():N}@groupride.local";
            var user = new User
            {
                Email = email,
                DisplayName = name,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword("demo"),
                CreatedAt = DateTime.UtcNow
            };
            db.Users.Add(user);
            ride.Members.Add(new RideMember
            {
                User = user,
                Role = role,
                InviteStatus = InviteStatus.Accepted,
                Status = RiderStatus.Riding,
                Attended = true
            });
            added++;
        }

        await db.SaveChangesAsync(ct);
    }

    private async Task BroadcastLocationsAsync(Guid rideId, AppDbContext db)
    {
        var members = await db.RideMembers
            .Include(m => m.User)
            .Where(m => m.RideId == rideId && m.LastLat != null)
            .ToListAsync();

        var locations = members.Select(m => new
        {
            m.UserId,
            m.User.DisplayName,
            Role = m.Role.ToString(),
            Status = m.Status.ToString(),
            Lat = m.LastLat,
            Lng = m.LastLng,
            SpeedMps = m.LastSpeedMps,
            Heading = m.LastHeading,
            m.LastLocationAt
        });

        await _hub.Clients.Group($"ride:{rideId}").SendAsync("RiderLocationsUpdated", locations);
    }

    private static List<LatLngPoint> BuildPath(Ride ride)
    {
        if (!string.IsNullOrWhiteSpace(ride.RoutePolyline))
        {
            try
            {
                using var doc = JsonDocument.Parse(ride.RoutePolyline);
                if (doc.RootElement.ValueKind == JsonValueKind.Array)
                {
                    var pts = new List<LatLngPoint>();
                    foreach (var el in doc.RootElement.EnumerateArray())
                    {
                        if (el.TryGetProperty("lat", out var lat) && el.TryGetProperty("lng", out var lng))
                            pts.Add(new LatLngPoint(lat.GetDouble(), lng.GetDouble()));
                    }
                    if (pts.Count >= 2) return pts;
                }
            }
            catch
            {
                // fall through
            }
        }

        var path = new List<LatLngPoint> { new(ride.MeetLat, ride.MeetLng) };
        path.AddRange(ride.Stops.OrderBy(s => s.SortOrder).Select(s => new LatLngPoint(s.Lat, s.Lng)));
        path.Add(new LatLngPoint(ride.DestinationLat, ride.DestinationLng));
        return path;
    }

    private static LatLngPoint PointAt(IReadOnlyList<LatLngPoint> path, double t)
    {
        if (path.Count == 1) return path[0];
        t = Math.Clamp(t, 0, 1);
        var total = 0.0;
        var segs = new List<double>();
        for (var i = 1; i < path.Count; i++)
        {
            var d = GeoMath.HaversineMeters(path[i - 1].Lat, path[i - 1].Lng, path[i].Lat, path[i].Lng);
            segs.Add(d);
            total += d;
        }
        if (total <= 0) return path[^1];

        var target = total * t;
        var acc = 0.0;
        for (var i = 0; i < segs.Count; i++)
        {
            if (acc + segs[i] >= target)
            {
                var local = segs[i] <= 0 ? 1 : (target - acc) / segs[i];
                var a = path[i];
                var b = path[i + 1];
                return new LatLngPoint(
                    a.Lat + (b.Lat - a.Lat) * local,
                    a.Lng + (b.Lng - a.Lng) * local);
            }
            acc += segs[i];
        }
        return path[^1];
    }

    private static double ApproximateKm(IReadOnlyList<LatLngPoint> path)
    {
        double m = 0;
        for (var i = 1; i < path.Count; i++)
            m += GeoMath.HaversineMeters(path[i - 1].Lat, path[i - 1].Lng, path[i].Lat, path[i].Lng);
        return m / 1000.0;
    }
}
