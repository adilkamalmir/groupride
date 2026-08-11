using GroupRide.Domain.Enums;

namespace GroupRide.Cohesion;

public record RiderPosition(
    Guid UserId,
    string DisplayName,
    RideRole Role,
    RiderStatus Status,
    double Lat,
    double Lng,
    double? SpeedMps,
    DateTime Timestamp);

public record GeoPoint(double Lat, double Lng);

public record SplitRider(Guid UserId, string DisplayName, double DistanceFromClusterMeters);

public record CohesionResult(
    bool IsSplit,
    GeoPoint ClusterCentroid,
    IReadOnlyList<SplitRider> SplitRiders,
    int SplitRiderCount,
    string Summary);

public record FuelEstimate(
    Guid UserId,
    string DisplayName,
    double RemainingRangeKm,
    bool NeedsFuelSoon);

public static class GeoMath
{
    private const double EarthRadiusMeters = 6371000;

    public static double HaversineMeters(double lat1, double lng1, double lat2, double lng2)
    {
        var dLat = DegreesToRadians(lat2 - lat1);
        var dLng = DegreesToRadians(lng2 - lng1);
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(DegreesToRadians(lat1)) * Math.Cos(DegreesToRadians(lat2)) *
                Math.Sin(dLng / 2) * Math.Sin(dLng / 2);
        var c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
        return EarthRadiusMeters * c;
    }

    public static GeoPoint Centroid(IEnumerable<GeoPoint> points)
    {
        var list = points.ToList();
        if (list.Count == 0) return new GeoPoint(0, 0);
        return new GeoPoint(list.Average(p => p.Lat), list.Average(p => p.Lng));
    }

    private static double DegreesToRadians(double degrees) => degrees * Math.PI / 180.0;
}
