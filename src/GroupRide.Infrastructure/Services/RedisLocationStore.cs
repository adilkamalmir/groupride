using System.Text.Json;
using GroupRide.Domain.Interfaces;
using Microsoft.Extensions.Logging;
using StackExchange.Redis;

namespace GroupRide.Infrastructure.Services;

/// <summary>
/// Hot-path location window in Redis.
/// Keys:
///   ride:{id}:latest  → hash userId → JSON ping
///   ride:{id}:trail   → sorted set score=unixMs, member=JSON ping (trimmed)
/// </summary>
public class RedisLocationStore : ILocationStore
{
    private readonly IConnectionMultiplexer _redis;
    private readonly ILogger<RedisLocationStore> _logger;
    private static readonly JsonSerializerOptions JsonOpts = new(JsonSerializerDefaults.Web);
    private const int MaxTrailPerRide = 2000;
    private static readonly TimeSpan Ttl = TimeSpan.FromHours(12);

    public RedisLocationStore(IConnectionMultiplexer redis, ILogger<RedisLocationStore> logger)
    {
        _redis = redis;
        _logger = logger;
    }

    public async Task WriteAsync(LocationPingRecord ping, CancellationToken ct = default)
    {
        try
        {
            var db = _redis.GetDatabase();
            var json = JsonSerializer.Serialize(ping, JsonOpts);
            var latestKey = LatestKey(ping.RideId);
            var trailKey = TrailKey(ping.RideId);
            var score = new DateTimeOffset(ping.Timestamp).ToUnixTimeMilliseconds();

            var batch = db.CreateBatch();
            _ = batch.HashSetAsync(latestKey, ping.UserId.ToString(), json);
            _ = batch.KeyExpireAsync(latestKey, Ttl);
            _ = batch.SortedSetAddAsync(trailKey, json, score);
            _ = batch.SortedSetRemoveRangeByRankAsync(trailKey, 0, -(MaxTrailPerRide + 1));
            _ = batch.KeyExpireAsync(trailKey, Ttl);
            batch.Execute();
            await Task.CompletedTask;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis location write failed for ride {RideId}", ping.RideId);
        }
    }

    public async Task<IReadOnlyList<LocationPingRecord>> GetLatestForRideAsync(Guid rideId, CancellationToken ct = default)
    {
        try
        {
            var db = _redis.GetDatabase();
            var entries = await db.HashGetAllAsync(LatestKey(rideId));
            return entries
                .Select(e => JsonSerializer.Deserialize<LocationPingRecord>((string)e.Value!, JsonOpts))
                .Where(p => p is not null)
                .Cast<LocationPingRecord>()
                .ToList();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis latest read failed for ride {RideId}", rideId);
            return Array.Empty<LocationPingRecord>();
        }
    }

    public async Task<IReadOnlyList<LocationPingRecord>> GetRecentAsync(Guid rideId, int limit = 200, CancellationToken ct = default)
    {
        try
        {
            var db = _redis.GetDatabase();
            var values = await db.SortedSetRangeByRankAsync(TrailKey(rideId), -limit, -1, Order.Descending);
            return values
                .Select(v => JsonSerializer.Deserialize<LocationPingRecord>((string)v!, JsonOpts))
                .Where(p => p is not null)
                .Cast<LocationPingRecord>()
                .ToList();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis trail read failed for ride {RideId}", rideId);
            return Array.Empty<LocationPingRecord>();
        }
    }

    public async Task<IReadOnlyList<LocationPingRecord>> GetRecentForUserAsync(Guid rideId, Guid userId, int limit = 100, CancellationToken ct = default)
    {
        var all = await GetRecentAsync(rideId, Math.Max(limit * 5, 200), ct);
        return all.Where(p => p.UserId == userId).Take(limit).ToList();
    }

    private static string LatestKey(Guid rideId) => $"ride:{rideId}:latest";
    private static string TrailKey(Guid rideId) => $"ride:{rideId}:trail";
}
