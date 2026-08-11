using GroupRide.Cohesion;
using GroupRide.Domain.Enums;

namespace GroupRide.Cohesion.Tests;

public class SplitDetectorTests
{
    private readonly SplitDetector _sut = new();

    [Fact]
    public void Detects_split_when_rider_beyond_threshold()
    {
        var riders = new List<RiderPosition>
        {
            Pos(Guid.NewGuid(), "Lead", RideRole.Leader, 45.3000, -75.9100),
            Pos(Guid.NewGuid(), "A", RideRole.Rider, 45.3001, -75.9101),
            Pos(Guid.NewGuid(), "B", RideRole.Rider, 45.3002, -75.9102),
            Pos(Guid.Parse("11111111-1111-1111-1111-111111111111"), "Lost", RideRole.Rider, 45.3100, -75.9200),
        };

        var result = _sut.Evaluate(riders, clusterRadiusMeters: 300, splitThresholdMeters: 500);

        Assert.True(result.IsSplit);
        Assert.Equal(1, result.SplitRiderCount);
        Assert.Contains(result.SplitRiders, r => r.DisplayName == "Lost");
        Assert.Contains("behind group", result.Summary);
    }

    [Fact]
    public void Group_together_when_all_close()
    {
        var riders = new List<RiderPosition>
        {
            Pos(Guid.NewGuid(), "Lead", RideRole.Leader, 45.3000, -75.9100),
            Pos(Guid.NewGuid(), "A", RideRole.Rider, 45.3001, -75.9101),
            Pos(Guid.NewGuid(), "B", RideRole.Rider, 45.30005, -75.91005),
        };

        var result = _sut.Evaluate(riders, 300, 500);
        Assert.False(result.IsSplit);
        Assert.Empty(result.SplitRiders);
    }

    [Fact]
    public void Haversine_known_distance()
    {
        // ~1km north of a point roughly
        var d = GeoMath.HaversineMeters(45.0, -75.0, 45.009, -75.0);
        Assert.InRange(d, 900, 1100);
    }

    private static RiderPosition Pos(Guid id, string name, RideRole role, double lat, double lng) =>
        new(id, name, role, RiderStatus.Riding, lat, lng, 15, DateTime.UtcNow);
}

public class FuelAnalyzerTests
{
    [Fact]
    public void Flags_riders_needing_fuel()
    {
        var analyzer = new FuelAnalyzer();
        var bikes = new[]
        {
            (Guid.NewGuid(), "Alex", 400.0, 120.0),
            (Guid.NewGuid(), "Sam", 250.0, 220.0),
            (Guid.NewGuid(), "Casey", 350.0, 320.0),
        };

        var estimates = analyzer.Analyze(bikes, horizonKm: 40);
        var msg = analyzer.BuildAggregateMessage(estimates, 40);

        Assert.Equal(2, estimates.Count(e => e.NeedsFuelSoon));
        Assert.Contains("2 riders need fuel", msg);
    }
}

public class CohesionStateTrackerTests
{
    [Fact]
    public void Emits_split_only_after_debounce()
    {
        var tracker = new CohesionStateTracker();
        var rideId = Guid.NewGuid();
        var splitResult = new CohesionResult(
            true,
            new GeoPoint(45, -75),
            new[] { new SplitRider(Guid.NewGuid(), "Lost", 800) },
            1,
            "1 rider is more than 500m behind group.");

        var first = tracker.Update(rideId, splitResult, splitDurationSeconds: 45);
        Assert.False(first.BecameSplit);

        // Simulate waiting by manually setting SplitSince in the past via multiple updates won't work
        // Use 0 duration for immediate
        var tracker2 = new CohesionStateTracker();
        var immediate = tracker2.Update(rideId, splitResult, splitDurationSeconds: 0);
        Assert.True(immediate.BecameSplit);
        Assert.True(immediate.ShouldSuggestRegroup);

        var again = tracker2.Update(rideId, splitResult, 0);
        Assert.False(again.BecameSplit);

        var joined = new CohesionResult(false, new GeoPoint(45, -75), Array.Empty<SplitRider>(), 0, "ok");
        var back = tracker2.Update(rideId, joined, 0);
        Assert.True(back.BecameJoined);
    }
}
