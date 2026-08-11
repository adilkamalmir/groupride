using GroupRide.Domain.Interfaces;
using Microsoft.Extensions.Logging;

namespace GroupRide.Infrastructure.Services;

/// <summary>In-memory fallback when Redis is unavailable.</summary>
public class InMemoryLocationStore : ILocationStore
{
    private readonly object _lock = new();
    private readonly Dictionary<Guid, Dictionary<Guid, LocationPingRecord>> _latest = new();
    private readonly Dictionary<Guid, List<LocationPingRecord>> _trails = new();
    private readonly ILogger<InMemoryLocationStore> _logger;

    public InMemoryLocationStore(ILogger<InMemoryLocationStore> logger) => _logger = logger;

    public Task WriteAsync(LocationPingRecord ping, CancellationToken ct = default)
    {
        lock (_lock)
        {
            if (!_latest.TryGetValue(ping.RideId, out var map))
            {
                map = new Dictionary<Guid, LocationPingRecord>();
                _latest[ping.RideId] = map;
            }
            map[ping.UserId] = ping;

            if (!_trails.TryGetValue(ping.RideId, out var trail))
            {
                trail = new List<LocationPingRecord>();
                _trails[ping.RideId] = trail;
            }
            trail.Add(ping);
            if (trail.Count > 2000)
                trail.RemoveRange(0, trail.Count - 2000);
        }
        return Task.CompletedTask;
    }

    public Task<IReadOnlyList<LocationPingRecord>> GetLatestForRideAsync(Guid rideId, CancellationToken ct = default)
    {
        lock (_lock)
        {
            if (!_latest.TryGetValue(rideId, out var map))
                return Task.FromResult<IReadOnlyList<LocationPingRecord>>(Array.Empty<LocationPingRecord>());
            return Task.FromResult<IReadOnlyList<LocationPingRecord>>(map.Values.ToList());
        }
    }

    public Task<IReadOnlyList<LocationPingRecord>> GetRecentAsync(Guid rideId, int limit = 200, CancellationToken ct = default)
    {
        lock (_lock)
        {
            if (!_trails.TryGetValue(rideId, out var trail))
                return Task.FromResult<IReadOnlyList<LocationPingRecord>>(Array.Empty<LocationPingRecord>());
            return Task.FromResult<IReadOnlyList<LocationPingRecord>>(
                trail.AsEnumerable().Reverse().Take(limit).ToList());
        }
    }

    public Task<IReadOnlyList<LocationPingRecord>> GetRecentForUserAsync(Guid rideId, Guid userId, int limit = 100, CancellationToken ct = default)
    {
        lock (_lock)
        {
            if (!_trails.TryGetValue(rideId, out var trail))
                return Task.FromResult<IReadOnlyList<LocationPingRecord>>(Array.Empty<LocationPingRecord>());
            return Task.FromResult<IReadOnlyList<LocationPingRecord>>(
                trail.Where(p => p.UserId == userId).Reverse().Take(limit).ToList());
        }
    }
}
