using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using GroupRide.Api.Auth;
using GroupRide.Api.Dtos;
using GroupRide.Api.Hubs;
using GroupRide.Api.Services;
using GroupRide.Cohesion;
using GroupRide.Domain.Entities;
using GroupRide.Domain.Enums;
using GroupRide.Domain.Interfaces;
using GroupRide.Infrastructure.Data;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace GroupRide.Api.Endpoints;

public static class RideEndpoints
{
    public static RouteGroupBuilder MapRideEndpoints(this WebApplication app)
    {
        var g = app.MapGroup("/api/rides").WithTags("Rides").RequireAuthorization();

        g.MapGet("/", async (ClaimsPrincipal principal, AppDbContext db) =>
        {
            var userId = principal.GetUserId();
            var rides = await db.Rides
                .Include(r => r.Stops)
                .Include(r => r.Members).ThenInclude(m => m.User)
                .Include(r => r.Invites)
                .Where(r => r.Members.Any(m => m.UserId == userId))
                .OrderByDescending(r => r.StartAt)
                .ToListAsync();
            return Results.Ok(rides.Select(MapRide));
        });

        g.MapGet("/{id:guid}", async (Guid id, ClaimsPrincipal principal, AppDbContext db) =>
        {
            var userId = principal.GetUserId();
            var ride = await LoadRide(db, id);
            if (ride is null) return Results.NotFound();
            if (ride.Members.All(m => m.UserId != userId)) return Results.Forbid();
            return Results.Ok(MapRide(ride));
        });

        g.MapPost("/", async (CreateRideRequest req, ClaimsPrincipal principal, AppDbContext db, IMapProvider maps) =>
        {
            var userId = principal.GetUserId();

            var meetLat = req.MeetLat;
            var meetLng = req.MeetLng;
            var destLat = req.DestinationLat;
            var destLng = req.DestinationLng;
            var meetName = req.MeetPointName;
            var destName = req.DestinationName;

            var resolvePlaces = req.ResolvePlaces ?? true;
            if (resolvePlaces)
            {
                if (meetLat == 0 && meetLng == 0)
                {
                    var meet = await maps.GeocodeAsync(meetName);
                    if (meet is null)
                        return Results.BadRequest(new { error = $"Could not geocode meeting point: {meetName}" });
                    meetLat = meet.Lat;
                    meetLng = meet.Lng;
                    meetName = meet.FormattedAddress;
                }

                if (destLat == 0 && destLng == 0)
                {
                    var dest = await maps.GeocodeAsync(destName);
                    if (dest is null)
                        return Results.BadRequest(new { error = $"Could not geocode destination: {destName}" });
                    destLat = dest.Lat;
                    destLng = dest.Lng;
                    destName = dest.FormattedAddress;
                }
            }

            var stops = new List<RideStop>();
            if (req.Stops is not null)
            {
                var order = 1;
                foreach (var s in req.Stops.OrderBy(x => x.SortOrder))
                {
                    var lat = s.Lat;
                    var lng = s.Lng;
                    var name = s.Name;
                    if (resolvePlaces && lat == 0 && lng == 0)
                    {
                        var place = await maps.GeocodeAsync(name);
                        if (place is null)
                            return Results.BadRequest(new { error = $"Could not geocode stop: {name}" });
                        lat = place.Lat;
                        lng = place.Lng;
                        name = place.FormattedAddress;
                    }

                    stops.Add(new RideStop
                    {
                        Name = name,
                        Kind = s.Kind,
                        Lat = lat,
                        Lng = lng,
                        SortOrder = s.SortOrder == 0 ? order : s.SortOrder,
                        DistanceFromStartKm = s.DistanceFromStartKm
                    });
                    order++;
                }
            }

            string? routePolyline = req.RoutePolyline;
            var buildRoute = req.BuildMotorcycleRoute ?? string.IsNullOrWhiteSpace(routePolyline);
            if (buildRoute)
            {
                var waypoints = new List<RouteWaypoint>
                {
                    new(meetName, meetLat, meetLng)
                };
                waypoints.AddRange(stops.OrderBy(s => s.SortOrder).Select(s => new RouteWaypoint(s.Name, s.Lat, s.Lng)));
                waypoints.Add(new RouteWaypoint(destName, destLat, destLng));

                var route = await maps.GetMotorcycleRouteAsync(waypoints);
                if (route?.DecodedPath is { Count: > 0 })
                {
                    routePolyline = JsonSerializer.Serialize(
                        route.DecodedPath.Select(p => new { lat = p.Lat, lng = p.Lng }));

                    if (stops.Count > 0 && route.DistanceMeters > 0)
                    {
                        var segmentKm = Math.Round(route.DistanceMeters / 1000.0 / (stops.Count + 1), 1);
                        var idx = 1;
                        foreach (var stop in stops.Where(s => s.DistanceFromStartKm is null))
                        {
                            stop.DistanceFromStartKm = segmentKm * idx;
                            idx++;
                        }
                    }
                }
                else if (route is not null)
                {
                    routePolyline ??= route.EncodedPolyline;
                }
            }

            var ride = new Ride
            {
                Name = req.Name,
                StartAt = req.StartAt.ToUniversalTime(),
                Status = RideStatus.Open,
                CreatedByUserId = userId,
                MeetPointName = meetName,
                MeetLat = meetLat,
                MeetLng = meetLng,
                DestinationName = destName,
                DestinationLat = destLat,
                DestinationLng = destLng,
                RoutePolyline = routePolyline,
                SplitThresholdMeters = req.SplitThresholdMeters ?? 500,
                SplitDurationSeconds = req.SplitDurationSeconds ?? 45
            };

            foreach (var s in stops)
                ride.Stops.Add(s);

            ride.Members.Add(new RideMember
            {
                UserId = userId,
                Role = RideRole.Leader,
                InviteStatus = InviteStatus.Accepted
            });

            ride.Invites.Add(new Invite
            {
                Token = GenerateToken(),
                ExpiresAt = DateTime.UtcNow.AddDays(60)
            });

            db.Rides.Add(ride);
            await db.SaveChangesAsync();

            ride = (await LoadRide(db, ride.Id))!;
            return Results.Created($"/api/rides/{ride.Id}", MapRide(ride));
        });

        g.MapPut("/{id:guid}", async (Guid id, UpdateRideRequest req, ClaimsPrincipal principal, AppDbContext db) =>
        {
            var userId = principal.GetUserId();
            var ride = await LoadRide(db, id);
            if (ride is null) return Results.NotFound();
            var me = ride.Members.FirstOrDefault(m => m.UserId == userId);
            if (me?.Role != RideRole.Leader) return Results.Forbid();

            if (req.Name is not null) ride.Name = req.Name;
            if (req.StartAt is not null) ride.StartAt = req.StartAt.Value.ToUniversalTime();
            if (req.MeetPointName is not null) ride.MeetPointName = req.MeetPointName;
            if (req.MeetLat is not null) ride.MeetLat = req.MeetLat.Value;
            if (req.MeetLng is not null) ride.MeetLng = req.MeetLng.Value;
            if (req.DestinationName is not null) ride.DestinationName = req.DestinationName;
            if (req.DestinationLat is not null) ride.DestinationLat = req.DestinationLat.Value;
            if (req.DestinationLng is not null) ride.DestinationLng = req.DestinationLng.Value;
            if (req.RoutePolyline is not null) ride.RoutePolyline = req.RoutePolyline;

            if (req.Stops is not null)
            {
                db.RideStops.RemoveRange(ride.Stops);
                ride.Stops.Clear();
                foreach (var s in req.Stops.OrderBy(x => x.SortOrder))
                {
                    ride.Stops.Add(new RideStop
                    {
                        Name = s.Name,
                        Kind = s.Kind,
                        Lat = s.Lat,
                        Lng = s.Lng,
                        SortOrder = s.SortOrder,
                        DistanceFromStartKm = s.DistanceFromStartKm
                    });
                }
            }

            await db.SaveChangesAsync();
            return Results.Ok(MapRide(await LoadRide(db, id)!));
        });

        g.MapDelete("/{id:guid}", async (Guid id, ClaimsPrincipal principal, AppDbContext db) =>
            await DeleteRideAsync(id, principal, db));

        // Alias for environments that block HTTP DELETE.
        g.MapPost("/{id:guid}/delete", async (Guid id, ClaimsPrincipal principal, AppDbContext db) =>
            await DeleteRideAsync(id, principal, db));

        g.MapPost("/{id:guid}/demo", async (Guid id, ClaimsPrincipal principal, DemoRideSimulator demo) =>
            await StartDemoAsync(id, principal, demo));

        g.MapPost("/{id:guid}/start-demo", async (Guid id, ClaimsPrincipal principal, DemoRideSimulator demo) =>
            await StartDemoAsync(id, principal, demo));

        g.MapPost("/{id:guid}/roles", async (Guid id, AssignRoleRequest req, ClaimsPrincipal principal, AppDbContext db, IHubContext<RideHub> hub) =>
        {
            var userId = principal.GetUserId();
            var ride = await LoadRide(db, id);
            if (ride is null) return Results.NotFound();
            if (ride.Members.FirstOrDefault(m => m.UserId == userId)?.Role != RideRole.Leader)
                return Results.Forbid();

            if (!Enum.TryParse<RideRole>(req.Role, true, out var role))
                return Results.BadRequest(new { error = "Invalid role" });

            var target = ride.Members.FirstOrDefault(m => m.UserId == req.UserId);
            if (target is null) return Results.NotFound();

            if (role == RideRole.Leader)
            {
                foreach (var m in ride.Members.Where(m => m.Role == RideRole.Leader))
                    m.Role = RideRole.Rider;
            }

            if (role == RideRole.Sweep)
            {
                foreach (var m in ride.Members.Where(m => m.Role == RideRole.Sweep))
                    m.Role = RideRole.Rider;
            }

            target.Role = role;
            await db.SaveChangesAsync();
            await hub.Clients.Group($"ride:{id}").SendAsync("RideStateChanged", MapRide(await LoadRide(db, id)!));
            return Results.Ok(MapRide(await LoadRide(db, id)!));
        });

        g.MapPost("/{id:guid}/start", async (Guid id, ClaimsPrincipal principal, AppDbContext db, IHubContext<RideHub> hub) =>
        {
            var userId = principal.GetUserId();
            var ride = await LoadRide(db, id);
            if (ride is null) return Results.NotFound();
            if (ride.Members.FirstOrDefault(m => m.UserId == userId)?.Role != RideRole.Leader)
                return Results.Forbid();

            ride.Status = RideStatus.Live;
            ride.StartedAt = DateTime.UtcNow;
            await db.SaveChangesAsync();
            await hub.Clients.Group($"ride:{id}").SendAsync("RideStateChanged", MapRide(await LoadRide(db, id)!));
            return Results.Ok(MapRide(await LoadRide(db, id)!));
        });

        g.MapPost("/{id:guid}/end", async (Guid id, ClaimsPrincipal principal, AppDbContext db, IHubContext<RideHub> hub, CohesionStateTracker tracker) =>
        {
            var userId = principal.GetUserId();
            var ride = await LoadRide(db, id);
            if (ride is null) return Results.NotFound();
            if (ride.Members.FirstOrDefault(m => m.UserId == userId)?.Role != RideRole.Leader)
                return Results.Forbid();

            ride.Status = RideStatus.Completed;
            ride.CompletedAt = DateTime.UtcNow;

            var duration = ride.StartedAt is null
                ? 0
                : (ride.CompletedAt.Value - ride.StartedAt.Value).TotalMinutes;

            var distance = ride.Members.Max(m => (double?)m.DistanceSinceStartKm) ?? 0;

            var attendance = ride.Members.Select(m => new
            {
                m.UserId,
                m.User.DisplayName,
                Role = m.Role.ToString(),
                m.Attended,
                m.DistanceSinceStartKm
            });

            var stops = ride.Stops.OrderBy(s => s.SortOrder).Select(s => new
            {
                s.Name, s.Kind, s.Lat, s.Lng, s.DistanceFromStartKm
            });

            var timeline = new RideTimeline
            {
                RideId = ride.Id,
                DistanceKm = Math.Round(distance, 1),
                DurationMinutes = Math.Round(duration, 1),
                RoutePolyline = ride.RoutePolyline,
                StopsJson = JsonSerializer.Serialize(stops),
                AttendanceJson = JsonSerializer.Serialize(attendance)
            };

            if (ride.Timeline is null)
                db.RideTimelines.Add(timeline);
            else
            {
                ride.Timeline.DistanceKm = timeline.DistanceKm;
                ride.Timeline.DurationMinutes = timeline.DurationMinutes;
                ride.Timeline.RoutePolyline = timeline.RoutePolyline;
                ride.Timeline.StopsJson = timeline.StopsJson;
                ride.Timeline.AttendanceJson = timeline.AttendanceJson;
            }

            await db.SaveChangesAsync();
            tracker.Clear(id);
            await hub.Clients.Group($"ride:{id}").SendAsync("RideStateChanged", MapRide(await LoadRide(db, id)!));
            return Results.Ok(MapRide(await LoadRide(db, id)!));
        });

        g.MapGet("/{id:guid}/timeline", async (Guid id, ClaimsPrincipal principal, AppDbContext db) =>
        {
            var userId = principal.GetUserId();
            var ride = await db.Rides.Include(r => r.Timeline).Include(r => r.Members)
                .FirstOrDefaultAsync(r => r.Id == id);
            if (ride is null) return Results.NotFound();
            if (ride.Members.All(m => m.UserId != userId)) return Results.Forbid();
            if (ride.Timeline is null) return Results.NotFound(new { error = "Ride not completed yet" });

            return Results.Ok(new TimelineDto(
                ride.Id, ride.Name, ride.Timeline.DistanceKm, ride.Timeline.DurationMinutes,
                ride.Timeline.RoutePolyline, ride.Timeline.StopsJson, ride.Timeline.AttendanceJson,
                ride.Timeline.PhotoUrlsJson, ride.Timeline.CreatedAt));
        });

        g.MapPost("/{id:guid}/timeline/photos", async (Guid id, AddTimelinePhotosRequest req, ClaimsPrincipal principal, AppDbContext db) =>
        {
            var userId = principal.GetUserId();
            var ride = await db.Rides.Include(r => r.Timeline).Include(r => r.Members)
                .FirstOrDefaultAsync(r => r.Id == id);
            if (ride is null) return Results.NotFound();
            if (ride.Members.All(m => m.UserId != userId)) return Results.Forbid();
            if (ride.Timeline is null) return Results.BadRequest(new { error = "Ride not completed yet" });

            var existing = string.IsNullOrWhiteSpace(ride.Timeline.PhotoUrlsJson)
                ? new List<string>()
                : (System.Text.Json.JsonSerializer.Deserialize<List<string>>(ride.Timeline.PhotoUrlsJson) ?? new());
            existing.AddRange(req.PhotoUrls.Where(u => !string.IsNullOrWhiteSpace(u)));
            ride.Timeline.PhotoUrlsJson = System.Text.Json.JsonSerializer.Serialize(existing.Distinct().ToList());
            await db.SaveChangesAsync();

            return Results.Ok(new TimelineDto(
                ride.Id, ride.Name, ride.Timeline.DistanceKm, ride.Timeline.DurationMinutes,
                ride.Timeline.RoutePolyline, ride.Timeline.StopsJson, ride.Timeline.AttendanceJson,
                ride.Timeline.PhotoUrlsJson, ride.Timeline.CreatedAt));
        });

        g.MapGet("/{id:guid}/alerts", async (Guid id, ClaimsPrincipal principal, AppDbContext db) =>
        {
            var userId = principal.GetUserId();
            var isMember = await db.RideMembers.AnyAsync(m => m.RideId == id && m.UserId == userId);
            if (!isMember) return Results.Forbid();

            var alerts = await db.Alerts.Where(a => a.RideId == id)
                .OrderByDescending(a => a.CreatedAt)
                .Take(100)
                .Select(a => new AlertDto(a.Id, a.Type.ToString(), a.Message, a.PayloadJson, a.RelatedUserId, a.CreatedAt, a.RecipientsJson))
                .ToListAsync();
            return Results.Ok(alerts);
        });

        g.MapGet("/{id:guid}/locations", async (Guid id, ClaimsPrincipal principal, AppDbContext db, GroupRide.Domain.Interfaces.ILocationStore store, int? limit) =>
        {
            var userId = principal.GetUserId();
            var isMember = await db.RideMembers.AnyAsync(m => m.RideId == id && m.UserId == userId);
            if (!isMember) return Results.Forbid();

            var take = Math.Clamp(limit ?? 200, 1, 1000);
            var hot = await store.GetRecentAsync(id, take);
            if (hot.Count > 0)
            {
                return Results.Ok(hot.Select(p => new LocationPingDto(
                    p.RideId, p.UserId, p.Lat, p.Lng, p.SpeedMps, p.Heading, p.AccuracyMeters, p.Timestamp, "redis")));
            }

            var archived = await db.LocationPings.AsNoTracking()
                .Where(p => p.RideId == id)
                .OrderByDescending(p => p.Timestamp)
                .Take(take)
                .Select(p => new LocationPingDto(p.RideId, p.UserId, p.Lat, p.Lng, p.SpeedMps, p.Heading, p.AccuracyMeters, p.Timestamp, "db"))
                .ToListAsync();
            return Results.Ok(archived);
        });

        g.MapGet("/{id:guid}/emergencies", async (Guid id, ClaimsPrincipal principal, AppDbContext db) =>
        {
            var userId = principal.GetUserId();
            var isMember = await db.RideMembers.AnyAsync(m => m.RideId == id && m.UserId == userId);
            if (!isMember) return Results.Forbid();

            var items = await db.Emergencies.AsNoTracking()
                .Include(e => e.User)
                .Where(e => e.RideId == id)
                .OrderByDescending(e => e.CreatedAt)
                .Select(e => new EmergencyDto(
                    e.Id, e.UserId, e.User.DisplayName, e.Type.ToString(), e.Lat, e.Lng, e.Notes,
                    e.CreatedAt, e.AcknowledgedByUserId, e.AcknowledgedAt, e.IsResolved))
                .ToListAsync();
            return Results.Ok(items);
        });

        g.MapPost("/{id:guid}/emergencies/{emergencyId:guid}/ack", async (Guid id, Guid emergencyId, ClaimsPrincipal principal, AppDbContext db, IHubContext<RideHub> hub) =>
        {
            var userId = principal.GetUserId();
            var member = await db.RideMembers.Include(m => m.User)
                .FirstOrDefaultAsync(m => m.RideId == id && m.UserId == userId);
            if (member is null) return Results.Forbid();

            var emergency = await db.Emergencies.FirstOrDefaultAsync(e => e.Id == emergencyId && e.RideId == id);
            if (emergency is null) return Results.NotFound();

            if (emergency.AcknowledgedByUserId is null)
            {
                emergency.AcknowledgedByUserId = userId;
                emergency.AcknowledgedAt = DateTime.UtcNow;
                await db.SaveChangesAsync();
            }

            await hub.Clients.Group($"ride:{id}").SendAsync("EmergencyAcknowledged", new
            {
                EmergencyId = emergency.Id,
                AcknowledgedByUserId = emergency.AcknowledgedByUserId,
                AcknowledgedByName = member.User.DisplayName,
                AcknowledgedAt = emergency.AcknowledgedAt
            });

            return Results.Ok(new { emergency.Id, emergency.AcknowledgedByUserId, emergency.AcknowledgedAt });
        });

        g.MapGet("/{id:guid}/invite", async (Guid id, ClaimsPrincipal principal, AppDbContext db) =>
        {
            var userId = principal.GetUserId();
            var ride = await LoadRide(db, id);
            if (ride is null) return Results.NotFound();
            if (ride.Members.FirstOrDefault(m => m.UserId == userId)?.Role != RideRole.Leader)
                return Results.Forbid();

            var invite = ride.Invites.FirstOrDefault(i => i.IsActive);
            if (invite is null)
            {
                invite = new Invite { RideId = id, Token = GenerateToken(), ExpiresAt = DateTime.UtcNow.AddDays(60) };
                db.Invites.Add(invite);
                await db.SaveChangesAsync();
            }

            var link = $"groupride://join/{invite.Token}";
            return Results.Ok(new
            {
                invite.Token,
                Link = link,
                QrPayload = link,
                ShareText = $"Join my group ride \"{ride.Name}\" on GroupRide: {link}"
            });
        });

        return g;
    }

    public static RouteGroupBuilder MapInviteEndpoints(this WebApplication app)
    {
        var g = app.MapGroup("/api/invites").WithTags("Invites");

        g.MapGet("/{token}", async (string token, AppDbContext db) =>
        {
            var invite = await db.Invites
                .Include(i => i.Ride).ThenInclude(r => r.Stops)
                .Include(i => i.Ride).ThenInclude(r => r.Members).ThenInclude(m => m.User)
                .Include(i => i.Ride).ThenInclude(r => r.Invites)
                .FirstOrDefaultAsync(i => i.Token == token && i.IsActive);

            if (invite is null) return Results.NotFound();
            if (invite.ExpiresAt is not null && invite.ExpiresAt < DateTime.UtcNow)
                return Results.BadRequest(new { error = "Invite expired" });

            return Results.Ok(MapRide(invite.Ride));
        });

        g.MapPost("/{token}/join", async (string token, ClaimsPrincipal principal, AppDbContext db) =>
        {
            if (principal.Identity?.IsAuthenticated != true)
                return Results.Unauthorized();

            var userId = principal.GetUserId();
            var invite = await db.Invites.Include(i => i.Ride).ThenInclude(r => r.Members)
                .FirstOrDefaultAsync(i => i.Token == token && i.IsActive);

            if (invite is null) return Results.NotFound();

            if (invite.Ride.Members.Any(m => m.UserId == userId))
            {
                var existing = await LoadRide(db, invite.RideId);
                return Results.Ok(MapRide(existing!));
            }

            invite.Ride.Members.Add(new RideMember
            {
                UserId = userId,
                Role = RideRole.Rider,
                InviteStatus = InviteStatus.Accepted
            });
            await db.SaveChangesAsync();
            return Results.Ok(MapRide((await LoadRide(db, invite.RideId))!));
        }).RequireAuthorization();

        return g;
    }

    private static async Task<IResult> DeleteRideAsync(Guid id, ClaimsPrincipal principal, AppDbContext db)
    {
        var userId = principal.GetUserId();
        var ride = await db.Rides
            .Include(r => r.Members)
            .Include(r => r.Stops)
            .Include(r => r.Invites)
            .Include(r => r.Alerts)
            .Include(r => r.Emergencies)
            .Include(r => r.Timeline)
            .FirstOrDefaultAsync(r => r.Id == id);
        if (ride is null) return Results.NotFound(new { error = "Ride not found" });

        var me = ride.Members.FirstOrDefault(m => m.UserId == userId);
        if (me is null)
            return Results.Json(new { error = "You are not a member of this ride." }, statusCode: StatusCodes.Status403Forbidden);

        var canDelete = me.Role == RideRole.Leader || ride.CreatedByUserId == userId;
        if (!canDelete)
            return Results.Json(new { error = "Only the ride leader can delete this ride." }, statusCode: StatusCodes.Status403Forbidden);

        var pings = await db.LocationPings.Where(p => p.RideId == id).ToListAsync();
        if (pings.Count > 0)
            db.LocationPings.RemoveRange(pings);

        db.Rides.Remove(ride);
        await db.SaveChangesAsync();
        return Results.NoContent();
    }

    private static async Task<IResult> StartDemoAsync(Guid id, ClaimsPrincipal principal, DemoRideSimulator demo)
    {
        var userId = principal.GetUserId();
        try
        {
            await demo.StartAsync(id, userId);
            return Results.Accepted($"/api/rides/{id}", new { rideId = id, demo = true });
        }
        catch (UnauthorizedAccessException)
        {
            return Results.Json(new { error = "Only the ride leader can start a demo." }, statusCode: StatusCodes.Status403Forbidden);
        }
        catch (InvalidOperationException ex)
        {
            return Results.BadRequest(new { error = ex.Message });
        }
    }

    private static async Task<Ride?> LoadRide(AppDbContext db, Guid id) =>
        await db.Rides
            .Include(r => r.Stops)
            .Include(r => r.Members).ThenInclude(m => m.User)
            .Include(r => r.Invites)
            .FirstOrDefaultAsync(r => r.Id == id);

    private static RideDto MapRide(Ride r)
    {
        var token = r.Invites.FirstOrDefault(i => i.IsActive)?.Token ?? "";
        return new RideDto(
            r.Id, r.Name, r.StartAt, r.Status.ToString(),
            r.MeetPointName, r.MeetLat, r.MeetLng,
            r.DestinationName, r.DestinationLat, r.DestinationLng,
            r.RoutePolyline, r.SplitThresholdMeters, r.SplitDurationSeconds, r.PingIntervalSeconds,
            r.StartedAt, r.CompletedAt, token,
            r.Stops.OrderBy(s => s.SortOrder).Select(s =>
                new RideStopDto(s.Id, s.Name, s.Kind, s.Lat, s.Lng, s.SortOrder, s.DistanceFromStartKm)).ToList(),
            r.Members.Select(m => new MemberDto(
                m.UserId, m.User.DisplayName, m.Role.ToString(), m.Status.ToString(),
                m.InviteStatus.ToString(), m.LastLat, m.LastLng, m.LastLocationAt)).ToList());
    }

    private static string GenerateToken()
    {
        var bytes = RandomNumberGenerator.GetBytes(9);
        return Convert.ToBase64String(bytes).Replace("+", "").Replace("/", "").Replace("=", "")[..12].ToLowerInvariant();
    }
}
