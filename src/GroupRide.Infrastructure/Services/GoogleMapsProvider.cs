using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using GroupRide.Domain.Interfaces;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace GroupRide.Infrastructure.Services;

public class GoogleMapsProvider : IMapProvider
{
    private readonly HttpClient _http;
    private readonly string _apiKey;
    private readonly ILogger<GoogleMapsProvider> _logger;
    private readonly LocalMapProvider _fallback = new();

    public GoogleMapsProvider(HttpClient http, IConfiguration config, ILogger<GoogleMapsProvider> logger)
    {
        _http = http;
        _apiKey = config["GoogleMaps:ApiKey"]
                  ?? config["GOOGLE_MAPS_API_KEY"]
                  ?? string.Empty;
        _logger = logger;
    }

    public bool IsConfigured => !string.IsNullOrWhiteSpace(_apiKey);

    public async Task<GeocodedPlace?> GeocodeAsync(string query, CancellationToken ct = default)
    {
        if (!IsConfigured || string.IsNullOrWhiteSpace(query))
            return null;

        var url =
            $"https://maps.googleapis.com/maps/api/geocode/json?address={Uri.EscapeDataString(query)}&key={_apiKey}";
        using var res = await _http.GetAsync(url, ct);
        res.EnsureSuccessStatusCode();
        var payload = await res.Content.ReadFromJsonAsync<GeocodeResponse>(cancellationToken: ct);
        var first = payload?.Results?.FirstOrDefault();
        if (first?.Geometry?.Location is null)
        {
            _logger.LogWarning("Geocode miss for {Query}: {Status}", query, payload?.Status);
            return null;
        }

        return new GeocodedPlace(
            query,
            first.FormattedAddress ?? query,
            first.Geometry.Location.Lat,
            first.Geometry.Location.Lng,
            first.PlaceId);
    }

    public async Task<IReadOnlyList<PlaceSuggestion>> AutocompleteAsync(
        string input,
        double? biasLat = null,
        double? biasLng = null,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(input) || input.Trim().Length < 2)
        {
            if (biasLat is not null && biasLng is not null)
                return await NearbySuggestionsAsync(biasLat.Value, biasLng.Value, null, ct);
            return Array.Empty<PlaceSuggestion>();
        }

        if (!IsConfigured)
            return await _fallback.AutocompleteAsync(input, biasLat, biasLng, ct);

        // When we know the user's location, prefer Text Search / Nearby (true local results).
        // Classic Autocomplete only lightly biases by location and often returns far-away hits.
        if (biasLat is not null && biasLng is not null)
        {
            var local = await LocalTextSearchAsync(input.Trim(), biasLat.Value, biasLng.Value, ct);
            if (local.Count > 0)
                return local;
        }

        var bias = biasLat is not null && biasLng is not null
            ? $"&location={biasLat.Value.ToString(CultureInfo.InvariantCulture)},{biasLng.Value.ToString(CultureInfo.InvariantCulture)}&radius=25000&origin={biasLat.Value.ToString(CultureInfo.InvariantCulture)},{biasLng.Value.ToString(CultureInfo.InvariantCulture)}"
            : string.Empty;

        var url =
            $"https://maps.googleapis.com/maps/api/place/autocomplete/json?input={Uri.EscapeDataString(input.Trim())}{bias}&key={_apiKey}";
        try
        {
            using var res = await _http.GetAsync(url, ct);
            res.EnsureSuccessStatusCode();
            var payload = await res.Content.ReadFromJsonAsync<AutocompleteResponse>(cancellationToken: ct);
            if (payload?.Status is not ("OK" or "ZERO_RESULTS") && payload?.Status is not null)
                _logger.LogWarning("Places autocomplete status={Status} for {Input}", payload.Status, input);

            return (payload?.Predictions ?? new List<AutocompletePrediction>())
                .Where(p => !string.IsNullOrWhiteSpace(p.PlaceId) && !string.IsNullOrWhiteSpace(p.Description))
                .Select(p => new PlaceSuggestion(
                    p.PlaceId!,
                    p.Description!,
                    p.StructuredFormatting?.MainText,
                    p.StructuredFormatting?.SecondaryText))
                .ToList();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Places autocomplete failed for {Input}", input);
            return await _fallback.AutocompleteAsync(input, biasLat, biasLng, ct);
        }
    }

    public async Task<IReadOnlyList<PlaceSuggestion>> NearbySuggestionsAsync(
        double lat, double lng, string? kind = null, CancellationToken ct = default)
    {
        if (!IsConfigured)
            return await _fallback.NearbySuggestionsAsync(lat, lng, kind, ct);

        var type = kind?.ToLowerInvariant() switch
        {
            "fuel" or "gas" => "gas_station",
            "lunch" or "food" or "restaurant" => "restaurant",
            "parking" => "parking",
            // Meeting points: cafes / parking near the rider work better than generic POI noise.
            _ => "cafe"
        };

        var results = await NearbySearchAsync(lat, lng, type, keyword: null, radiusMeters: 12000, ct);
        if (results.Count == 0 && type == "cafe")
            results = await NearbySearchAsync(lat, lng, "parking", keyword: null, radiusMeters: 12000, ct);
        if (results.Count == 0)
            return await _fallback.NearbySuggestionsAsync(lat, lng, kind, ct);
        return results;
    }

    private async Task<IReadOnlyList<PlaceSuggestion>> LocalTextSearchAsync(
        string input, double lat, double lng, CancellationToken ct)
    {
        var loc = $"{lat.ToString(CultureInfo.InvariantCulture)},{lng.ToString(CultureInfo.InvariantCulture)}";
        // Text Search ranks by relevance near location; Nearby+keyword is a strong fallback.
        var textUrl =
            $"https://maps.googleapis.com/maps/api/place/textsearch/json?query={Uri.EscapeDataString(input)}&location={loc}&radius=25000&key={_apiKey}";
        try
        {
            using var res = await _http.GetAsync(textUrl, ct);
            if (res.IsSuccessStatusCode)
            {
                var payload = await res.Content.ReadFromJsonAsync<PlacesNearbyResponse>(cancellationToken: ct);
                var fromText = MapPlaceResults(payload?.Results, lat, lng);
                if (fromText.Count > 0)
                    return fromText;
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Text search failed for {Input}", input);
        }

        return await NearbySearchAsync(lat, lng, type: null, keyword: input, radiusMeters: 25000, ct);
    }

    private async Task<IReadOnlyList<PlaceSuggestion>> NearbySearchAsync(
        double lat, double lng, string? type, string? keyword, int radiusMeters, CancellationToken ct)
    {
        var loc = $"{lat.ToString(CultureInfo.InvariantCulture)},{lng.ToString(CultureInfo.InvariantCulture)}";
        var typeQs = string.IsNullOrWhiteSpace(type) ? string.Empty : $"&type={Uri.EscapeDataString(type)}";
        var keywordQs = string.IsNullOrWhiteSpace(keyword) ? string.Empty : $"&keyword={Uri.EscapeDataString(keyword)}";
        var url =
            $"https://maps.googleapis.com/maps/api/place/nearbysearch/json?location={loc}&radius={radiusMeters}{typeQs}{keywordQs}&key={_apiKey}";
        try
        {
            using var res = await _http.GetAsync(url, ct);
            if (!res.IsSuccessStatusCode)
                return Array.Empty<PlaceSuggestion>();
            var payload = await res.Content.ReadFromJsonAsync<PlacesNearbyResponse>(cancellationToken: ct);
            return MapPlaceResults(payload?.Results, lat, lng);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Nearby search failed");
            return Array.Empty<PlaceSuggestion>();
        }
    }

    private static IReadOnlyList<PlaceSuggestion> MapPlaceResults(
        List<PlaceResult>? results, double biasLat, double biasLng)
    {
        return (results ?? new List<PlaceResult>())
            .Where(p => p.Geometry?.Location is not null && !string.IsNullOrWhiteSpace(p.Name))
            .Select(p =>
            {
                var d = Haversine(biasLat, biasLng, p.Geometry!.Location!.Lat, p.Geometry.Location.Lng);
                var area = p.Vicinity ?? p.FormattedAddress ?? string.Empty;
                var secondary = area;
                if (d > 0)
                {
                    var km = d / 1000.0;
                    secondary = string.IsNullOrWhiteSpace(area)
                        ? $"{km:0.0} km away"
                        : $"{area} · {km:0.0} km";
                }
                return (
                    Suggestion: new PlaceSuggestion(
                        p.PlaceId ?? $"nearby:{p.Name}",
                        string.IsNullOrWhiteSpace(area) ? p.Name! : $"{p.Name}, {area}",
                        p.Name,
                        secondary),
                    Distance: d);
            })
            .OrderBy(x => x.Distance)
            .Take(8)
            .Select(x => x.Suggestion)
            .ToList();
    }

    public async Task<IReadOnlyList<GeocodedPlace>> SuggestStopsAlongRouteAsync(
        IReadOnlyList<LatLngPoint> path, CancellationToken ct = default)
    {
        if (path.Count == 0)
            return Array.Empty<GeocodedPlace>();

        if (!IsConfigured)
            return await _fallback.SuggestStopsAlongRouteAsync(path, ct);

        var samples = SamplePath(path, 3);
        var results = new List<GeocodedPlace>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var sample in samples)
        {
            foreach (var type in new[] { "gas_station", "restaurant" })
            {
                var url =
                    $"https://maps.googleapis.com/maps/api/place/nearbysearch/json?location={sample.Lat.ToString(CultureInfo.InvariantCulture)},{sample.Lng.ToString(CultureInfo.InvariantCulture)}&radius=5000&type={type}&key={_apiKey}";
                try
                {
                    using var res = await _http.GetAsync(url, ct);
                    if (!res.IsSuccessStatusCode) continue;
                    var payload = await res.Content.ReadFromJsonAsync<PlacesNearbyResponse>(cancellationToken: ct);
                    foreach (var p in (payload?.Results ?? Enumerable.Empty<PlaceResult>()).Take(2))
                    {
                        if (p.Geometry?.Location is null || string.IsNullOrWhiteSpace(p.Name)) continue;
                        var key = p.PlaceId ?? p.Name!;
                        if (!seen.Add(key)) continue;
                        var address = p.Vicinity is null ? p.Name! : $"{p.Name}, {p.Vicinity}";
                        results.Add(new GeocodedPlace(
                            p.Name!,
                            address,
                            p.Geometry.Location.Lat,
                            p.Geometry.Location.Lng,
                            p.PlaceId));
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Stop suggestion failed for {Type}", type);
                }
            }
        }

        if (results.Count == 0)
            return await _fallback.SuggestStopsAlongRouteAsync(path, ct);

        return results.Take(8).ToList();
    }

    private static List<LatLngPoint> SamplePath(IReadOnlyList<LatLngPoint> path, int count)
    {
        if (path.Count == 0) return [];
        if (path.Count == 1) return [path[0]];
        var samples = new List<LatLngPoint>();
        for (var i = 1; i <= count; i++)
        {
            var idx = (int)Math.Round((path.Count - 1) * (i / (double)(count + 1)));
            samples.Add(path[Math.Clamp(idx, 0, path.Count - 1)]);
        }
        return samples;
    }

    public async Task<GeocodedPlace?> GetPlaceDetailsAsync(string placeId, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(placeId))
            return null;

        if (!IsConfigured)
            return await _fallback.GetPlaceDetailsAsync(placeId, ct);

        var url =
            $"https://maps.googleapis.com/maps/api/place/details/json?place_id={Uri.EscapeDataString(placeId)}&fields=place_id,name,formatted_address,geometry&key={_apiKey}";
        try
        {
            using var res = await _http.GetAsync(url, ct);
            res.EnsureSuccessStatusCode();
            var payload = await res.Content.ReadFromJsonAsync<PlaceDetailsResponse>(cancellationToken: ct);
            var result = payload?.Result;
            if (result?.Geometry?.Location is null)
            {
                _logger.LogWarning("Place details miss for {PlaceId}: {Status}", placeId, payload?.Status);
                return null;
            }

            var address = result.FormattedAddress ?? result.Name ?? placeId;
            return new GeocodedPlace(address, address, result.Geometry.Location.Lat, result.Geometry.Location.Lng, result.PlaceId ?? placeId);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Place details failed for {PlaceId}", placeId);
            return null;
        }
    }

    public async Task<RouteDirections?> GetMotorcycleRouteAsync(
        IReadOnlyList<RouteWaypoint> waypoints, CancellationToken ct = default)
    {
        if (waypoints.Count < 2)
            return null;

        if (!IsConfigured)
            return await StraightLineRoute(waypoints);

        // Prefer two-wheeler (motorbike) mode; fall back to driving if unavailable in region.
        var route = await RequestDirectionsAsync(waypoints, "two_wheeler", ct);
        if (route is null)
        {
            _logger.LogInformation("two_wheeler unavailable; falling back to driving for motorcycle ride");
            route = await RequestDirectionsAsync(waypoints, "driving", ct);
        }

        return route ?? await StraightLineRoute(waypoints);
    }

    public Task<RouteDirections?> GetDirectionsAsync(
        double fromLat, double fromLng, double toLat, double toLng, CancellationToken ct = default) =>
        GetMotorcycleRouteAsync(
            new[] { new RouteWaypoint(null, fromLat, fromLng), new RouteWaypoint(null, toLat, toLng) },
            ct);

    public async Task<IReadOnlyList<RegroupPointCandidate>> FindRegroupPointsNearAsync(
        double lat, double lng, double radiusMeters, CancellationToken ct = default)
    {
        if (!IsConfigured)
            return await _fallback.FindRegroupPointsNearAsync(lat, lng, radiusMeters, ct);

        var types = new[] { "gas_station", "parking", "rest_stop" };
        var results = new List<RegroupPointCandidate>();

        foreach (var type in types)
        {
            var url =
                $"https://maps.googleapis.com/maps/api/place/nearbysearch/json?location={lat.ToString(CultureInfo.InvariantCulture)},{lng.ToString(CultureInfo.InvariantCulture)}&radius={Math.Min(radiusMeters, 50000).ToString(CultureInfo.InvariantCulture)}&type={type}&key={_apiKey}";
            try
            {
                using var res = await _http.GetAsync(url, ct);
                if (!res.IsSuccessStatusCode) continue;
                var payload = await res.Content.ReadFromJsonAsync<PlacesNearbyResponse>(cancellationToken: ct);
                foreach (var p in payload?.Results ?? Enumerable.Empty<PlaceResult>())
                {
                    if (p.Geometry?.Location is null) continue;
                    var d = Haversine(lat, lng, p.Geometry.Location.Lat, p.Geometry.Location.Lng);
                    results.Add(new RegroupPointCandidate(
                        p.Name ?? type,
                        type switch
                        {
                            "gas_station" => "gas",
                            "parking" => "parking",
                            _ => "rest"
                        },
                        p.Geometry.Location.Lat,
                        p.Geometry.Location.Lng,
                        d));
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Places nearby failed for {Type}", type);
            }
        }

        if (results.Count == 0)
            return await _fallback.FindRegroupPointsNearAsync(lat, lng, radiusMeters, ct);

        return results.OrderBy(r => r.DistanceMeters).Take(10).ToList();
    }

    private async Task<RouteDirections?> RequestDirectionsAsync(
        IReadOnlyList<RouteWaypoint> waypoints, string mode, CancellationToken ct)
    {
        var origin = waypoints[0];
        var dest = waypoints[^1];
        var via = waypoints.Skip(1).Take(waypoints.Count - 2)
            .Select(w => $"{w.Lat.ToString(CultureInfo.InvariantCulture)},{w.Lng.ToString(CultureInfo.InvariantCulture)}");
        var waypointsParam = via.Any()
            ? $"&waypoints={Uri.EscapeDataString(string.Join("|", via))}"
            : string.Empty;

        var url =
            $"https://maps.googleapis.com/maps/api/directions/json?origin={origin.Lat.ToString(CultureInfo.InvariantCulture)},{origin.Lng.ToString(CultureInfo.InvariantCulture)}&destination={dest.Lat.ToString(CultureInfo.InvariantCulture)},{dest.Lng.ToString(CultureInfo.InvariantCulture)}{waypointsParam}&mode={mode}&key={_apiKey}";

        using var res = await _http.GetAsync(url, ct);
        res.EnsureSuccessStatusCode();
        var payload = await res.Content.ReadFromJsonAsync<DirectionsResponse>(cancellationToken: ct);
        if (payload?.Status is not ("OK" or "ok") || payload.Routes is null || payload.Routes.Count == 0)
        {
            _logger.LogWarning("Directions {Mode} status={Status}", mode, payload?.Status);
            return null;
        }

        var route = payload.Routes[0];
        var encoded = route.OverviewPolyline?.Points;
        if (string.IsNullOrWhiteSpace(encoded))
            return null;

        var legs = route.Legs ?? new List<DirectionLeg>();
        var distance = legs.Sum(l => l.Distance?.Value ?? 0);
        var duration = legs.Sum(l => l.Duration?.Value ?? 0);
        var decoded = PolylineCodec.Decode(encoded);

        return new RouteDirections(distance, duration, encoded, mode, decoded);
    }

    private static Task<RouteDirections?> StraightLineRoute(IReadOnlyList<RouteWaypoint> waypoints)
    {
        double dist = 0;
        for (var i = 1; i < waypoints.Count; i++)
            dist += Haversine(waypoints[i - 1].Lat, waypoints[i - 1].Lng, waypoints[i].Lat, waypoints[i].Lng);
        var duration = dist / (80_000.0 / 3600.0);
        var path = waypoints.Select(w => new LatLngPoint(w.Lat, w.Lng)).ToList();
        var encoded = string.Join(",", path.Select(p => $"{p.Lat}:{p.Lng}"));
        return Task.FromResult<RouteDirections?>(new RouteDirections(dist, duration, encoded, "straight", path));
    }

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

    private sealed class GeocodeResponse
    {
        public string? Status { get; set; }
        public List<GeocodeResult>? Results { get; set; }
    }

    private sealed class GeocodeResult
    {
        [JsonPropertyName("formatted_address")]
        public string? FormattedAddress { get; set; }
        [JsonPropertyName("place_id")]
        public string? PlaceId { get; set; }
        public GeometryBlock? Geometry { get; set; }
    }

    private sealed class GeometryBlock
    {
        public LatLngBlock? Location { get; set; }
    }

    private sealed class LatLngBlock
    {
        public double Lat { get; set; }
        public double Lng { get; set; }
    }

    private sealed class DirectionsResponse
    {
        public string? Status { get; set; }
        public List<DirectionRoute>? Routes { get; set; }
    }

    private sealed class DirectionRoute
    {
        [JsonPropertyName("overview_polyline")]
        public OverviewPolyline? OverviewPolyline { get; set; }
        public List<DirectionLeg>? Legs { get; set; }
    }

    private sealed class OverviewPolyline
    {
        public string? Points { get; set; }
    }

    private sealed class DirectionLeg
    {
        public TextValue? Distance { get; set; }
        public TextValue? Duration { get; set; }
    }

    private sealed class TextValue
    {
        public double Value { get; set; }
    }

    private sealed class PlacesNearbyResponse
    {
        public List<PlaceResult>? Results { get; set; }
    }

    private sealed class PlaceResult
    {
        public string? Name { get; set; }
        [JsonPropertyName("place_id")]
        public string? PlaceId { get; set; }
        public string? Vicinity { get; set; }
        [JsonPropertyName("formatted_address")]
        public string? FormattedAddress { get; set; }
        public GeometryBlock? Geometry { get; set; }
    }

    private sealed class AutocompleteResponse
    {
        public string? Status { get; set; }
        public List<AutocompletePrediction>? Predictions { get; set; }
    }

    private sealed class AutocompletePrediction
    {
        [JsonPropertyName("place_id")]
        public string? PlaceId { get; set; }
        public string? Description { get; set; }
        [JsonPropertyName("structured_formatting")]
        public StructuredFormatting? StructuredFormatting { get; set; }
    }

    private sealed class StructuredFormatting
    {
        [JsonPropertyName("main_text")]
        public string? MainText { get; set; }
        [JsonPropertyName("secondary_text")]
        public string? SecondaryText { get; set; }
    }

    private sealed class PlaceDetailsResponse
    {
        public string? Status { get; set; }
        public PlaceDetailsResult? Result { get; set; }
    }

    private sealed class PlaceDetailsResult
    {
        [JsonPropertyName("place_id")]
        public string? PlaceId { get; set; }
        public string? Name { get; set; }
        [JsonPropertyName("formatted_address")]
        public string? FormattedAddress { get; set; }
        public GeometryBlock? Geometry { get; set; }
    }
}

/// <summary>Google encoded polyline algorithm.</summary>
public static class PolylineCodec
{
    public static IReadOnlyList<LatLngPoint> Decode(string encoded)
    {
        var poly = new List<LatLngPoint>();
        int index = 0, lat = 0, lng = 0;
        while (index < encoded.Length)
        {
            int b, shift = 0, result = 0;
            do
            {
                b = encoded[index++] - 63;
                result |= (b & 0x1f) << shift;
                shift += 5;
            } while (b >= 0x20);
            var dlat = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
            lat += dlat;

            shift = 0;
            result = 0;
            do
            {
                b = encoded[index++] - 63;
                result |= (b & 0x1f) << shift;
                shift += 5;
            } while (b >= 0x20);
            var dlng = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
            lng += dlng;

            poly.Add(new LatLngPoint(lat / 1e5, lng / 1e5));
        }
        return poly;
    }
}
