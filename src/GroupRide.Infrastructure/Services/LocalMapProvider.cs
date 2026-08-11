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
        string input,
        double? biasLat = null,
        double? biasLng = null,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(input) || input.Trim().Length < 2)
        {
            if (biasLat is not null && biasLng is not null)
                return NearbySuggestionsAsync(biasLat.Value, biasLng.Value, null, ct);
            return Task.FromResult<IReadOnlyList<PlaceSuggestion>>(Array.Empty<PlaceSuggestion>());
        }

        var q = input.Trim();
        var placeHits = KnownPlaces
            .Select(kv =>
            {
                var d = biasLat is null || biasLng is null
                    ? 0
                    : Haversine(biasLat.Value, biasLng.Value, kv.Value.Lat, kv.Value.Lng);
                return (Name: kv.Key, Address: kv.Value.Address, d);
            })
            .Where(x =>
                x.Name.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                x.Address.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                q.Contains(x.Name, StringComparison.OrdinalIgnoreCase));

        var pointHits = KnownPoints
            .Select(p =>
            {
                var d = biasLat is null || biasLng is null
                    ? 0
                    : Haversine(biasLat.Value, biasLng.Value, p.Lat, p.Lng);
                return (p, d);
            })
            .Where(x =>
                x.p.Name.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                x.p.Kind.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                (q.Contains("gas", StringComparison.OrdinalIgnoreCase) && x.p.Kind == "gas") ||
                (q.Contains("fuel", StringComparison.OrdinalIgnoreCase) && x.p.Kind == "gas") ||
                (q.Contains("coffee", StringComparison.OrdinalIgnoreCase) && x.p.Name.Contains("Tim", StringComparison.OrdinalIgnoreCase)));

        var hits = placeHits
            .Select(x => new PlaceSuggestion($"local:{x.Name}", x.Address, x.Name, $"{x.d / 1000:0.0} km away"))
            .Concat(pointHits.Select(x => new PlaceSuggestion(
                $"local:{x.p.Name}",
                x.p.Name,
                x.p.Name,
                $"{x.p.Kind} · {x.d / 1000:0.0} km")))
            .GroupBy(s => s.PlaceId, StringComparer.OrdinalIgnoreCase)
            .Select(g => g.First())
            .OrderBy(s =>
            {
                var secondary = s.SecondaryText ?? "";
                var idx = secondary.IndexOf(" km", StringComparison.Ordinal);
                if (idx > 0)
                {
                    var num = secondary[..idx].Split(' ', StringSplitOptions.RemoveEmptyEntries).LastOrDefault();
                    if (double.TryParse(num, out var km)) return km;
                }
                return 999d;
            })
            .Take(6)
            .ToList();

        return Task.FromResult<IReadOnlyList<PlaceSuggestion>>(hits);
    }

    public Task<IReadOnlyList<PlaceSuggestion>> NearbySuggestionsAsync(
        double lat, double lng, string? kind = null, CancellationToken ct = default)
    {
        var kindFilter = kind?.ToLowerInvariant();
        var fromPoints = KnownPoints
            .Select(p => p with { DistanceMeters = Haversine(lat, lng, p.Lat, p.Lng) })
            .Where(p => p.DistanceMeters <= 40_000)
            .Where(p => kindFilter is null
                        || (kindFilter is "fuel" or "gas" && p.Kind == "gas")
                        || (kindFilter is "lunch" or "food" or "restaurant" && p.Kind is "rest" or "parking")
                        || (kindFilter == "parking" && p.Kind == "parking")
                        || (kindFilter is "cafe" or "meeting" && p.Kind is "parking" or "rest"));

        var fromPlaces = KnownPlaces
            .Select(kv => (
                Name: kv.Key,
                Address: kv.Value.Address,
                Lat: kv.Value.Lat,
                Lng: kv.Value.Lng,
                Distance: Haversine(lat, lng, kv.Value.Lat, kv.Value.Lng)))
            .Where(p => p.Distance <= 40_000)
            .Select(p => new PlaceSuggestion(
                $"local:{p.Name}",
                p.Address,
                p.Name,
                $"{p.Distance / 1000:0.0} km away"));

        var hits = fromPoints
            .Select(p => new PlaceSuggestion(
                $"local:{p.Name}",
                p.Name,
                p.Name,
                $"{p.Kind} · {p.DistanceMeters / 1000:0.0} km"))
            .Concat(fromPlaces)
            .GroupBy(s => s.PlaceId, StringComparer.OrdinalIgnoreCase)
            .Select(g => g.First())
            .OrderBy(s =>
            {
                // Parse "X.Y km" from secondary when present for stable local ordering.
                var secondary = s.SecondaryText ?? "";
                var idx = secondary.IndexOf(" km", StringComparison.Ordinal);
                if (idx > 0)
                {
                    var num = secondary[..idx].Split(' ').LastOrDefault();
                    if (double.TryParse(num, out var km)) return km;
                }
                return 999d;
            })
            .Take(8)
            .ToList();

        return Task.FromResult<IReadOnlyList<PlaceSuggestion>>(hits);
    }

    public Task<IReadOnlyList<GeocodedPlace>> SuggestStopsAlongRouteAsync(
        IReadOnlyList<LatLngPoint> path, CancellationToken ct = default)
    {
        if (path.Count == 0)
            return Task.FromResult<IReadOnlyList<GeocodedPlace>>(Array.Empty<GeocodedPlace>());

        var mid = path[path.Count / 2];
        var stops = KnownPoints
            .Where(p => p.Kind is "gas" or "rest" or "parking")
            .Select(p => p with { DistanceMeters = Haversine(mid.Lat, mid.Lng, p.Lat, p.Lng) })
            .OrderBy(p => p.DistanceMeters)
            .Take(6)
            .Select(p => new GeocodedPlace(p.Name, p.Name, p.Lat, p.Lng, $"local:{p.Name}"))
            .ToList();

        return Task.FromResult<IReadOnlyList<GeocodedPlace>>(stops);
    }

    public Task<GeocodedPlace?> GetPlaceDetailsAsync(string placeId, CancellationToken ct = default)
    {
        if (placeId.StartsWith("local:", StringComparison.OrdinalIgnoreCase))
        {
            var key = placeId["local:".Length..];
            if (KnownPlaces.TryGetValue(key, out var hit))
                return Task.FromResult<GeocodedPlace?>(new GeocodedPlace(key, hit.Address, hit.Lat, hit.Lng, placeId));

            var point = KnownPoints.FirstOrDefault(p =>
                p.Name.Equals(key, StringComparison.OrdinalIgnoreCase));
            if (point is not null)
                return Task.FromResult<GeocodedPlace?>(
                    new GeocodedPlace(point.Name, point.Name, point.Lat, point.Lng, placeId));
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
