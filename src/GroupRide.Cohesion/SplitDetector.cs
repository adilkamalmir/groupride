namespace GroupRide.Cohesion;

/// <summary>
/// Detects when riders fall behind the main pack.
/// Uses a majority-cluster approach: find the densest group within clusterRadius,
/// then flag riders beyond splitThreshold as split.
/// </summary>
public class SplitDetector
{
    public CohesionResult Evaluate(
        IReadOnlyList<RiderPosition> riders,
        double clusterRadiusMeters = 300,
        double splitThresholdMeters = 500)
    {
        if (riders.Count == 0)
        {
            return new CohesionResult(false, new GeoPoint(0, 0), Array.Empty<SplitRider>(), 0, "No riders");
        }

        if (riders.Count == 1)
        {
            var only = riders[0];
            return new CohesionResult(
                false,
                new GeoPoint(only.Lat, only.Lng),
                Array.Empty<SplitRider>(),
                0,
                "Single rider");
        }

        // Score each rider by how many others are within clusterRadius
        var bestCluster = riders
            .Select(seed =>
            {
                var members = riders
                    .Where(r => GeoMath.HaversineMeters(seed.Lat, seed.Lng, r.Lat, r.Lng) <= clusterRadiusMeters)
                    .ToList();
                return members;
            })
            .OrderByDescending(c => c.Count)
            .First();

        // Prefer leader-containing cluster if same size
        var leader = riders.FirstOrDefault(r => r.Role == Domain.Enums.RideRole.Leader);
        if (leader is not null)
        {
            var leaderCluster = riders
                .Where(r => GeoMath.HaversineMeters(leader.Lat, leader.Lng, r.Lat, r.Lng) <= clusterRadiusMeters)
                .ToList();
            if (leaderCluster.Count >= bestCluster.Count)
                bestCluster = leaderCluster;
        }

        var centroid = GeoMath.Centroid(bestCluster.Select(r => new GeoPoint(r.Lat, r.Lng)));
        var clusterIds = bestCluster.Select(r => r.UserId).ToHashSet();

        var splitRiders = riders
            .Where(r => !clusterIds.Contains(r.UserId))
            .Select(r =>
            {
                var dist = GeoMath.HaversineMeters(centroid.Lat, centroid.Lng, r.Lat, r.Lng);
                return new SplitRider(r.UserId, r.DisplayName, dist);
            })
            .Where(s => s.DistanceFromClusterMeters > splitThresholdMeters)
            .OrderByDescending(s => s.DistanceFromClusterMeters)
            .ToList();

        var isSplit = splitRiders.Count > 0;
        var summary = isSplit
            ? $"{splitRiders.Count} rider{(splitRiders.Count == 1 ? "" : "s")} are more than {splitThresholdMeters:0}m behind group."
            : "Group is together.";

        return new CohesionResult(isSplit, centroid, splitRiders, splitRiders.Count, summary);
    }
}
