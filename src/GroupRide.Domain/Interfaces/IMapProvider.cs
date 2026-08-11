namespace GroupRide.Domain.Interfaces;

public interface IMapProvider
{
    Task<IReadOnlyList<RegroupPointCandidate>> FindRegroupPointsNearAsync(
        double lat, double lng, double radiusMeters, CancellationToken ct = default);

    Task<RouteDirections?> GetDirectionsAsync(
        double fromLat, double fromLng, double toLat, double toLng, CancellationToken ct = default);

    /// <summary>Geocode a free-text place name to coordinates.</summary>
    Task<GeocodedPlace?> GeocodeAsync(string query, CancellationToken ct = default);

    /// <summary>Place name autocomplete suggestions (Google Places or local fallback).</summary>
    Task<IReadOnlyList<PlaceSuggestion>> AutocompleteAsync(
        string input,
        double? biasLat = null,
        double? biasLng = null,
        CancellationToken ct = default);

    /// <summary>Nearby place suggestions around a point (for empty-field focus / current location).</summary>
    Task<IReadOnlyList<PlaceSuggestion>> NearbySuggestionsAsync(
        double lat,
        double lng,
        string? kind = null,
        CancellationToken ct = default);

    /// <summary>Suggest fuel/food stops near sample points along a route path.</summary>
    Task<IReadOnlyList<GeocodedPlace>> SuggestStopsAlongRouteAsync(
        IReadOnlyList<LatLngPoint> path,
        CancellationToken ct = default);

    /// <summary>Resolve a place_id from autocomplete to lat/lng + address.</summary>
    Task<GeocodedPlace?> GetPlaceDetailsAsync(string placeId, CancellationToken ct = default);

    /// <summary>
    /// Motorcycle route through ordered waypoints (meet → stops → destination).
    /// Uses Google two-wheeler mode when available, otherwise driving fallback.
    /// </summary>
    Task<RouteDirections?> GetMotorcycleRouteAsync(
        IReadOnlyList<RouteWaypoint> waypoints, CancellationToken ct = default);
}

public record RegroupPointCandidate(
    string Name,
    string Kind,
    double Lat,
    double Lng,
    double DistanceMeters);

public record RouteDirections(
    double DistanceMeters,
    double DurationSeconds,
    string EncodedPolyline,
    string TravelMode,
    IReadOnlyList<LatLngPoint>? DecodedPath = null);

public record RouteWaypoint(string? Name, double Lat, double Lng);

public record GeocodedPlace(
    string Query,
    string FormattedAddress,
    double Lat,
    double Lng,
    string? PlaceId);

public record PlaceSuggestion(
    string PlaceId,
    string Description,
    string? MainText,
    string? SecondaryText);

public record LatLngPoint(double Lat, double Lng);
