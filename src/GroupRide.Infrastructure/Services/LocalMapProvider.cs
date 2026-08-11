using GroupRide.Domain.Interfaces;

namespace GroupRide.Infrastructure.Services;

/// <summary>
/// Local MVP map provider with hardcoded Ottawa-area regroup POIs.
/// Used when Google Maps API key is not configured.
/// </summary>
public class LocalMapProvider : IMapProvider
{
    private static readonly RegroupPointCandidate[] KnownPoints =
    [
        new("Tim Hortons Kanata", "parking", 45.3001, -75.9105, 0),
        new("Canadian Tire Gas Barrhaven", "gas", 45.2750, -75.7360, 0),
        new("Renfrew Petro-Canada", "gas", 45.4747, -76.6831, 0),
        new("Calabogie Motorsports Park", "parking", 45.3008, -76.7175, 0),
        new("Arnprior Rest Stop", "rest", 45.4333, -76.3500, 0),
        new("Mississippi Mills Parking", "parking", 45.2260, -76.1940, 0),
    ];

    private static readonly Dictionary<string, (double Lat, double Lng, string Address)> KnownPlaces = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Tim Hortons Kanata"] = (45.3001, -75.9105, "Tim Hortons, Kanata, ON"),
        ["Kanata"] = (45.3001, -75.9105, "Kanata, ON"),
        ["Calabogie"] = (45.3008, -76.7175, "Calabogie, ON"),
        ["Renfrew"] = (45.4747, -76.6831, "Renfrew, ON"),
        ["Ottawa"] = (45.4215, -75.6972, "Ottawa, ON"),
        ["Arnprior"] = (45.4333, -76.3500, "Arnprior, ON"),
        ["Barrhaven"] = (45.2750, -75.7360, "Barrhaven, ON"),
    };

    public Task<IReadOnlyList<RegroupPointCandidate>> FindRegroupPointsNearAsync(
        double lat, double lng, double radiusMeters, CancellationToken ct = default)
    {
        var results = KnownPoints
            .Select(p =>
            {
                var d = Haversine(lat, lng, p.Lat, p.Lng);
                return p with { DistanceMeters = d };
            })
            .Where(p => p.DistanceMeters <= radiusMeters)
            .OrderBy(p => p.DistanceMeters)
            .ToList();

        return Task.FromResult<IReadOnlyList<RegroupPointCandidate>>(results);
    }

    public Task<GeocodedPlace?> GeocodeAsync(string query, CancellationToken ct = default)
    {
        if (KnownPlaces.TryGetValue(query.Trim(), out var hit))
            return Task.FromResult<GeocodedPlace?>(new GeocodedPlace(query, hit.Address, hit.Lat, hit.Lng, null));

        foreach (var kv in KnownPlaces)
        {
            if (query.Contains(kv.Key, StringComparison.OrdinalIgnoreCase) ||
                kv.Key.Contains(query, StringComparison.OrdinalIgnoreCase))
            {
                return Task.FromResult<GeocodedPlace?>(
                    new GeocodedPlace(query, kv.Value.Address, kv.Value.Lat, kv.Value.Lng, null));
            }
        }

        return Task.FromResult<GeocodedPlace?>(null);
    }

    public Task<IReadOnlyList<PlaceSuggestion>> AutocompleteAsync(
        string input, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(input) || input.Trim().Length < 2)
            return Task.FromResult<IReadOnlyList<PlaceSuggestion>>(Array.Empty<PlaceSuggestion>());

        var q = input.Trim();
        var hits = KnownPlaces
            .Where(kv =>
                kv.Key.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                kv.Value.Address.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                q.Contains(kv.Key, StringComparison.OrdinalIgnoreCase))
            .Select(kv => new PlaceSuggestion(
                $"local:{kv.Key}",
                kv.Value.Address,
                kv.Key,
                kv.Value.Address))
            .Take(6)
            .ToList();

        return Task.FromResult<IReadOnlyList<PlaceSuggestion>>(hits);
    }

    public Task<GeocodedPlace?> GetPlaceDetailsAsync(string placeId, CancellationToken ct = default)
    {
        if (placeId.StartsWith("local:", StringComparison.OrdinalIgnoreCase))
        {
            var key = placeId["local:".Length..];
            if (KnownPlaces.TryGetValue(key, out var hit))
                return Task.FromResult<GeocodedPlace?>(new GeocodedPlace(key, hit.Address, hit.Lat, hit.Lng, placeId));
        }

        return GeocodeAsync(placeId, ct);
    }

    public Task<RouteDirections?> GetMotorcycleRouteAsync(
        IReadOnlyList<RouteWaypoint> waypoints, CancellationToken ct = default)
    {
        if (waypoints.Count < 2) return Task.FromResult<RouteDirections?>(null);
        double dist = 0;
        for (var i = 1; i < waypoints.Count; i++)
            dist += Haversine(waypoints[i - 1].Lat, waypoints[i - 1].Lng, waypoints[i].Lat, waypoints[i].Lng);
        var duration = dist / (80_000.0 / 3600.0);
        var path = waypoints.Select(w => new LatLngPoint(w.Lat, w.Lng)).ToList();
        return Task.FromResult<RouteDirections?>(
            new RouteDirections(dist, duration, "local", "two_wheeler", path));
    }

    public Task<RouteDirections?> GetDirectionsAsync(
        double fromLat, double fromLng, double toLat, double toLng, CancellationToken ct = default) =>
        GetMotorcycleRouteAsync(
            new[] { new RouteWaypoint(null, fromLat, fromLng), new RouteWaypoint(null, toLat, toLng) },
            ct);

    private static double Haversine(double lat1, double lng1, double lat2, double lng2)
    {
        const double R = 6371000;
        var dLat = (lat2 - lat1) * Math.PI / 180;
        var dLng = (lng2 - lng1) * Math.PI / 180;
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(lat1 * Math.PI / 180) * Math.Cos(lat2 * Math.PI / 180) *
                Math.Sin(dLng / 2) * Math.Sin(dLng / 2);
        return R * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
    }
}
