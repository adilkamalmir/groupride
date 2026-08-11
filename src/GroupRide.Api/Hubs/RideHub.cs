using System.Text.Json;
using GroupRide.Api.Dtos;
using GroupRide.Cohesion;
using GroupRide.Domain.Entities;
using GroupRide.Domain.Enums;
using GroupRide.Domain.Interfaces;
using GroupRide.Infrastructure.Data;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace GroupRide.Api.Hubs;

public class RideHub : Hub
{
    private readonly AppDbContext _db;
    private readonly SplitDetector _splitDetector;
    private readonly CohesionStateTracker _tracker;
    private readonly FuelAnalyzer _fuelAnalyzer;
    private readonly IMapProvider _maps;
    private readonly IPushSender _push;
    private readonly ILocationStore _locations;
    private readonly ILogger<RideHub> _logger;

    public RideHub(
        AppDbContext db,
        SplitDetector splitDetector,
        CohesionStateTracker tracker,
        FuelAnalyzer fuelAnalyzer,
        IMapProvider maps,
        IPushSender push,
        ILocationStore locations,
        ILogger<RideHub> logger)
    {
        _db = db;
        _splitDetector = splitDetector;
        _tracker = tracker;
        _fuelAnalyzer = fuelAnalyzer;
        _maps = maps;
        _push = push;
        _locations = locations;
        _logger = logger;
    }

    public async Task JoinRide(Guid rideId)
    {
        var userId = GetUserId();
        var member = await _db.RideMembers.FirstOrDefaultAsync(m => m.RideId == rideId && m.UserId == userId);
        if (member is null)
            throw new HubException("Not a member of this ride");

        await Groups.AddToGroupAsync(Context.ConnectionId, GroupName(rideId));
        await Clients.Caller.SendAsync("JoinedRide", rideId);
    }

    public async Task LeaveRide(Guid rideId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, GroupName(rideId));
    }

    public async Task UpdateLocation(Guid rideId, LocationUpdateDto dto)
    {
        var userId = GetUserId();
        var ride = await _db.Rides
            .Include(r => r.Members).ThenInclude(m => m.User).ThenInclude(u => u.Bike)
            .Include(r => r.Stops)
            .FirstOrDefaultAsync(r => r.Id == rideId);

        if (ride is null || ride.Status != RideStatus.Live)
            throw new HubException("Ride is not live");

        var member = ride.Members.FirstOrDefault(m => m.UserId == userId)
                     ?? throw new HubException("Not a member");

        var ts = dto.Timestamp?.ToUniversalTime() ?? DateTime.UtcNow;
        var prevLat = member.LastLat;
        var prevLng = member.LastLng;

        if (prevLat is not null && prevLng is not null)
        {
            var delta = GeoMath.HaversineMeters(prevLat.Value, prevLng.Value, dto.Lat, dto.Lng) / 1000.0;
            member.DistanceSinceStartKm += delta;
        }

        member.LastLat = dto.Lat;
        member.LastLng = dto.Lng;
        member.LastSpeedMps = dto.SpeedMps;
        member.LastHeading = dto.Heading;
        member.LastLocationAt = ts;
        member.Attended = true;

        // Auto-stopped if speed near zero for this ping
        if (member.Status != RiderStatus.Emergency && member.Status != RiderStatus.FuelNeeded)
        {
            if (dto.SpeedMps is not null && dto.SpeedMps < 0.5)
                member.Status = RiderStatus.Stopped;
            else if (member.Status == RiderStatus.Stopped)
                member.Status = RiderStatus.Riding;
        }

        var pingRecord = new LocationPingRecord(
            rideId, userId, dto.Lat, dto.Lng, dto.SpeedMps, dto.Heading, dto.AccuracyMeters, ts);

        // Hot path: Redis recent window
        await _locations.WriteAsync(pingRecord);

        // Archive to Postgres
        _db.LocationPings.Add(new LocationPing
        {
            RideId = rideId,
            UserId = userId,
            Lat = dto.Lat,
            Lng = dto.Lng,
            SpeedMps = dto.SpeedMps,
            Heading = dto.Heading,
            AccuracyMeters = dto.AccuracyMeters,
            Timestamp = ts
        });

        // Update bike distance for fuel
        var bike = await _db.BikeProfiles.FirstOrDefaultAsync(b => b.UserId == userId);
        if (bike is not null && prevLat is not null && prevLng is not null)
        {
            var delta = GeoMath.HaversineMeters(prevLat.Value, prevLng.Value, dto.Lat, dto.Lng) / 1000.0;
            bike.DistanceSinceFillKm = (bike.DistanceSinceFillKm ?? 0) + delta;
        }

        await _db.SaveChangesAsync();

        var locations = ride.Members
            .Where(m => m.LastLat is not null)
            .Select(m => new
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

        await Clients.Group(GroupName(rideId)).SendAsync("RiderLocationsUpdated", locations);

        // Cohesion evaluation
        var positions = ride.Members
            .Where(m => m.LastLat is not null && m.LastLng is not null)
            .Select(m => new RiderPosition(
                m.UserId, m.User.DisplayName, m.Role, m.Status,
                m.LastLat!.Value, m.LastLng!.Value, m.LastSpeedMps, m.LastLocationAt ?? ts))
            .ToList();

        var cohesion = _splitDetector.Evaluate(positions, 300, ride.SplitThresholdMeters);
        var (becameSplit, becameJoined, shouldSuggestRegroup, _) =
            _tracker.Update(rideId, cohesion, ride.SplitDurationSeconds);

        var allMemberIds = ride.Members.Select(m => m.UserId).ToList();

        if (becameSplit)
        {
            var alert = CreateAlert(
                rideId, AlertType.Split, cohesion.Summary, allMemberIds,
                JsonSerializer.Serialize(new
                {
                    cohesion.SplitRiderCount,
                    Riders = cohesion.SplitRiders,
                    Centroid = cohesion.ClusterCentroid
                }));
            _db.Alerts.Add(alert);
            await _db.SaveChangesAsync();

            await Clients.Group(GroupName(rideId)).SendAsync("AlertRaised", ToAlertDto(alert));
            await _push.SendToUsersAsync(allMemberIds, "Group split", cohesion.Summary);
        }

        if (becameJoined)
        {
            var alert = CreateAlert(rideId, AlertType.Rejoined, "Group has regrouped.", allMemberIds);
            _db.Alerts.Add(alert);
            await _db.SaveChangesAsync();
            await Clients.Group(GroupName(rideId)).SendAsync("AlertRaised", ToAlertDto(alert));
        }

        if (shouldSuggestRegroup && cohesion.IsSplit)
        {
            var lead = positions.FirstOrDefault(p => p.Role == RideRole.Leader) ?? positions.First();
            var pois = await _maps.FindRegroupPointsNearAsync(lead.Lat, lead.Lng, 15_000);
            var best = pois.FirstOrDefault() ?? new RegroupPointCandidate("Pull over safely", "rest", lead.Lat, lead.Lng, 0);
            var distKm = best.DistanceMeters / 1000.0;
            var msg = $"Regroup recommended in {distKm:0.0} km at {best.Name}";

            // Regroup primarily for leader + sweep
            var recipients = ride.Members
                .Where(m => m.Role is RideRole.Leader or RideRole.Sweep)
                .Select(m => m.UserId)
                .DefaultIfEmpty(lead.UserId)
                .ToList();

            var alert = CreateAlert(rideId, AlertType.Regroup, msg, recipients, JsonSerializer.Serialize(best));
            _db.Alerts.Add(alert);
            await _db.SaveChangesAsync();
            _tracker.MarkRegroupSuggested(rideId);

            await Clients.Group(GroupName(rideId)).SendAsync("RegroupSuggested", new
            {
                Message = msg,
                Point = best
            });
            await Clients.Group(GroupName(rideId)).SendAsync("AlertRaised", ToAlertDto(alert));
        }

        // Periodic fuel check (cheap): every location update from leader
        if (member.Role == RideRole.Leader)
        {
            var bikes = ride.Members
                .Where(m => m.User.Bike is not null)
                .Select(m => (
                    m.UserId,
                    m.User.DisplayName,
                    m.User.Bike!.TypicalRangeKm,
                    m.User.Bike.DistanceSinceFillKm ?? 0));
            var estimates = _fuelAnalyzer.Analyze(bikes);
            var fuelMsg = _fuelAnalyzer.BuildAggregateMessage(estimates);
            if (fuelMsg is not null)
            {
                await Clients.Group(GroupName(rideId)).SendAsync("FuelStatus", new
                {
                    Message = fuelMsg,
                    Estimates = estimates
                });
            }
        }
    }

    public async Task SetStatus(Guid rideId, SetStatusRequest req)
    {
        var userId = GetUserId();
        if (!Enum.TryParse<RiderStatus>(req.Status, true, out var status))
            throw new HubException("Invalid status");

        var member = await _db.RideMembers.Include(m => m.User)
            .FirstOrDefaultAsync(m => m.RideId == rideId && m.UserId == userId)
            ?? throw new HubException("Not a member");

        member.Status = status;
        await _db.SaveChangesAsync();

        await Clients.Group(GroupName(rideId)).SendAsync("RiderStatusChanged", new
        {
            member.UserId,
            member.User.DisplayName,
            Status = status.ToString()
        });
    }

    public async Task SendAnnouncement(Guid rideId, AnnouncementRequest req)
    {
        var userId = GetUserId();
        var member = await _db.RideMembers.Include(m => m.User)
            .FirstOrDefaultAsync(m => m.RideId == rideId && m.UserId == userId)
            ?? throw new HubException("Not a member");

        if (member.Role != RideRole.Leader)
            throw new HubException("Only the leader can announce");

        var recipients = await _db.RideMembers.Where(m => m.RideId == rideId).Select(m => m.UserId).ToListAsync();
        var alert = CreateAlert(rideId, AlertType.Announcement, req.Message, recipients, relatedUserId: userId);
        _db.Alerts.Add(alert);
        await _db.SaveChangesAsync();

        await Clients.Group(GroupName(rideId)).SendAsync("AlertRaised", ToAlertDto(alert));
    }

    public async Task RaiseEmergency(Guid rideId, EmergencyRequest req)
    {
        var userId = GetUserId();
        if (!Enum.TryParse<EmergencyType>(req.Type, true, out var type))
            throw new HubException("Invalid emergency type");

        var member = await _db.RideMembers.Include(m => m.User)
            .FirstOrDefaultAsync(m => m.RideId == rideId && m.UserId == userId)
            ?? throw new HubException("Not a member");

        member.Status = RiderStatus.Emergency;
        member.LastLat = req.Lat;
        member.LastLng = req.Lng;
        member.LastLocationAt = DateTime.UtcNow;

        var emergency = new Emergency
        {
            RideId = rideId,
            UserId = userId,
            Type = type,
            Lat = req.Lat,
            Lng = req.Lng,
            Notes = req.Notes
        };
        _db.Emergencies.Add(emergency);

        var recipients = await _db.RideMembers.Where(m => m.RideId == rideId).Select(m => m.UserId).ToListAsync();
        var alert = CreateAlert(
            rideId, AlertType.Emergency,
            $"{member.User.DisplayName} needs help: {type}",
            recipients,
            JsonSerializer.Serialize(new { emergency.Id, type, req.Lat, req.Lng }),
            userId);
        _db.Alerts.Add(alert);
        await _db.SaveChangesAsync();

        var others = await _db.RideMembers
            .Where(m => m.RideId == rideId && m.UserId != userId)
            .Include(m => m.User)
            .ToListAsync();

        var payload = others.Select(o =>
        {
            double? dist = null;
            if (o.LastLat is not null && o.LastLng is not null)
                dist = GeoMath.HaversineMeters(req.Lat, req.Lng, o.LastLat.Value, o.LastLng.Value);
            return new
            {
                o.UserId,
                DistanceMeters = dist
            };
        });

        await Clients.Group(GroupName(rideId)).SendAsync("EmergencyRaised", new
        {
            EmergencyId = emergency.Id,
            UserId = userId,
            DisplayName = member.User.DisplayName,
            Type = type.ToString(),
            Lat = req.Lat,
            Lng = req.Lng,
            Notes = req.Notes,
            Distances = payload
        });
        await Clients.Group(GroupName(rideId)).SendAsync("AlertRaised", ToAlertDto(alert));
        await _push.SendToUsersAsync(others.Select(o => o.UserId), "Emergency", alert.Message);
    }

    public async Task AcknowledgeEmergency(Guid rideId, Guid emergencyId)
    {
        var userId = GetUserId();
        var member = await _db.RideMembers.Include(m => m.User)
            .FirstOrDefaultAsync(m => m.RideId == rideId && m.UserId == userId)
            ?? throw new HubException("Not a member");

        var emergency = await _db.Emergencies
            .Include(e => e.User)
            .FirstOrDefaultAsync(e => e.Id == emergencyId && e.RideId == rideId)
            ?? throw new HubException("Emergency not found");

        if (emergency.AcknowledgedByUserId is null)
        {
            emergency.AcknowledgedByUserId = userId;
            emergency.AcknowledgedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync();
        }

        await Clients.Group(GroupName(rideId)).SendAsync("EmergencyAcknowledged", new
        {
            EmergencyId = emergency.Id,
            AcknowledgedByUserId = emergency.AcknowledgedByUserId,
            AcknowledgedByName = member.User.DisplayName,
            AcknowledgedAt = emergency.AcknowledgedAt
        });
    }

    public async Task ResolveEmergency(Guid rideId, Guid emergencyId)
    {
        var userId = GetUserId();
        _ = await _db.RideMembers.FirstOrDefaultAsync(m => m.RideId == rideId && m.UserId == userId)
            ?? throw new HubException("Not a member");

        var emergency = await _db.Emergencies
            .FirstOrDefaultAsync(e => e.Id == emergencyId && e.RideId == rideId)
            ?? throw new HubException("Emergency not found");

        emergency.IsResolved = true;
        emergency.AcknowledgedByUserId ??= userId;
        emergency.AcknowledgedAt ??= DateTime.UtcNow;

        var rider = await _db.RideMembers.FirstOrDefaultAsync(m => m.RideId == rideId && m.UserId == emergency.UserId);
        if (rider is not null && rider.Status == RiderStatus.Emergency)
            rider.Status = RiderStatus.Riding;

        await _db.SaveChangesAsync();
        await Clients.Group(GroupName(rideId)).SendAsync("EmergencyResolved", new { EmergencyId = emergency.Id });
        await Clients.Group(GroupName(rideId)).SendAsync("RiderStatusChanged", new
        {
            UserId = emergency.UserId,
            Status = RiderStatus.Riding.ToString()
        });
    }

    public async Task<RejoinTargetDto> RequestRejoinTarget(Guid rideId, RejoinRequest req)
    {
        var userId = GetUserId();
        var ride = await _db.Rides
            .Include(r => r.Members).ThenInclude(m => m.User)
            .Include(r => r.Stops)
            .FirstOrDefaultAsync(r => r.Id == rideId)
            ?? throw new HubException("Ride not found");

        var me = ride.Members.FirstOrDefault(m => m.UserId == userId)
                 ?? throw new HubException("Not a member");

        if (me.LastLat is null || me.LastLng is null)
            throw new HubException("No location yet");

        double targetLat, targetLng;
        string label, targetType;

        if (string.Equals(req.Target, "next_stop", StringComparison.OrdinalIgnoreCase))
        {
            var next = ride.Stops.OrderBy(s => s.SortOrder).FirstOrDefault();
            if (next is null)
            {
                targetLat = ride.DestinationLat;
                targetLng = ride.DestinationLng;
                label = ride.DestinationName;
            }
            else
            {
                targetLat = next.Lat;
                targetLng = next.Lng;
                label = next.Name;
            }
            targetType = "next_stop";
        }
        else
        {
            var others = ride.Members
                .Where(m => m.UserId != userId && m.LastLat is not null)
                .ToList();
            if (others.Count == 0)
            {
                targetLat = ride.MeetLat;
                targetLng = ride.MeetLng;
                label = "Meeting point";
            }
            else
            {
                var lead = others.FirstOrDefault(m => m.Role == RideRole.Leader) ?? others.First();
                // Prefer cluster centroid of others
                var centroid = GeoMath.Centroid(others.Select(o => new GeoPoint(o.LastLat!.Value, o.LastLng!.Value)));
                targetLat = centroid.Lat;
                targetLng = centroid.Lng;
                label = $"Group (near {lead.User.DisplayName})";
            }
            targetType = "group";
        }

        var directions = await _maps.GetDirectionsAsync(me.LastLat.Value, me.LastLng.Value, targetLat, targetLng);
        return new RejoinTargetDto(
            targetType,
            label,
            targetLat,
            targetLng,
            directions?.DistanceMeters ?? GeoMath.HaversineMeters(me.LastLat.Value, me.LastLng.Value, targetLat, targetLng),
            directions?.DurationSeconds ?? 0,
            directions?.EncodedPolyline);
    }

    private Guid GetUserId()
    {
        var sub = Context.User?.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value
                  ?? Context.User?.FindFirst("sub")?.Value
                  ?? throw new HubException("Unauthorized");
        return Guid.Parse(sub);
    }

    private static string GroupName(Guid rideId) => $"ride:{rideId}";

    private static Alert CreateAlert(
        Guid rideId,
        AlertType type,
        string message,
        IEnumerable<Guid> recipients,
        string? payloadJson = null,
        Guid? relatedUserId = null) =>
        new()
        {
            RideId = rideId,
            Type = type,
            Message = message,
            PayloadJson = payloadJson,
            RelatedUserId = relatedUserId,
            RecipientsJson = JsonSerializer.Serialize(recipients.Distinct())
        };

    private static AlertDto ToAlertDto(Alert a) =>
        new(a.Id, a.Type.ToString(), a.Message, a.PayloadJson, a.RelatedUserId, a.CreatedAt, a.RecipientsJson);
}
