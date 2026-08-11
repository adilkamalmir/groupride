namespace GroupRide.Domain.Interfaces;

public interface ILocationStore
{
    /// <summary>Write ping to hot window (Redis) and return the stored record.</summary>
    Task WriteAsync(LocationPingRecord ping, CancellationToken ct = default);

    /// <summary>Latest ping per user for a ride from the hot window.</summary>
    Task<IReadOnlyList<LocationPingRecord>> GetLatestForRideAsync(Guid rideId, CancellationToken ct = default);

    /// <summary>Recent pings for a ride (newest first), capped.</summary>
    Task<IReadOnlyList<LocationPingRecord>> GetRecentAsync(Guid rideId, int limit = 200, CancellationToken ct = default);

    /// <summary>Recent pings for one rider.</summary>
    Task<IReadOnlyList<LocationPingRecord>> GetRecentForUserAsync(Guid rideId, Guid userId, int limit = 100, CancellationToken ct = default);
}

public record LocationPingRecord(
    Guid RideId,
    Guid UserId,
    double Lat,
    double Lng,
    double? SpeedMps,
    double? Heading,
    double? AccuracyMeters,
    DateTime Timestamp);
