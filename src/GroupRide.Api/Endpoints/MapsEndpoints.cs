using GroupRide.Api.Dtos;
using GroupRide.Domain.Interfaces;

namespace GroupRide.Api.Endpoints;

public static class MapsEndpoints
{
    public static RouteGroupBuilder MapMapsEndpoints(this WebApplication app)
    {
        var g = app.MapGroup("/api/maps").WithTags("Maps");

        g.MapGet("/config", (IConfiguration config, IMapProvider maps) =>
        {
            var serverKey = config["GoogleMaps:ApiKey"] ?? config["GOOGLE_MAPS_API_KEY"];
            var provider = string.IsNullOrWhiteSpace(serverKey) ? "local" : "google";
            return Results.Ok(new
            {
                provider,
                supportsMotorcycleRouting = provider == "google"
            });
        });

        g.MapGet("/geocode", async (string q, IMapProvider maps) =>
        {
            if (string.IsNullOrWhiteSpace(q))
                return Results.BadRequest(new { error = "q is required" });
            var place = await maps.GeocodeAsync(q);
            return place is null ? Results.NotFound(new { error = "No results" }) : Results.Ok(place);
        });

        g.MapGet("/autocomplete", async (string? q, double? lat, double? lng, IMapProvider maps) =>
        {
            var suggestions = await maps.AutocompleteAsync(q ?? string.Empty, lat, lng);
            return Results.Ok(suggestions);
        });

        g.MapGet("/nearby", async (double lat, double lng, string? kind, IMapProvider maps) =>
        {
            var suggestions = await maps.NearbySuggestionsAsync(lat, lng, kind);
            return Results.Ok(suggestions);
        });

        // Alias for clients / older docs that look under /places-nearby
        g.MapGet("/places-nearby", async (double lat, double lng, string? kind, IMapProvider maps) =>
        {
            var suggestions = await maps.NearbySuggestionsAsync(lat, lng, kind);
            return Results.Ok(suggestions);
        });

        g.MapGet("/place", async (string placeId, IMapProvider maps) =>
        {
            if (string.IsNullOrWhiteSpace(placeId))
                return Results.BadRequest(new { error = "placeId is required" });
            var place = await maps.GetPlaceDetailsAsync(placeId);
            return place is null ? Results.NotFound(new { error = "No results" }) : Results.Ok(place);
        });

        g.MapPost("/route", async (MotorcycleRouteRequest req, IMapProvider maps) =>
        {
            if (req.Waypoints is null || req.Waypoints.Count < 2)
                return Results.BadRequest(new { error = "At least 2 waypoints required" });

            var points = req.Waypoints
                .Select(w => new RouteWaypoint(w.Name, w.Lat, w.Lng))
                .ToList();

            var route = await maps.GetMotorcycleRouteAsync(points);
            if (route is null)
                return Results.NotFound(new { error = "No route found" });

            return Results.Ok(new MotorcycleRouteResponse(
                route.DistanceMeters,
                route.DurationSeconds,
                route.TravelMode,
                route.EncodedPolyline,
                route.DecodedPath?.Select(p => new LatLngDto(p.Lat, p.Lng)).ToList() ?? new List<LatLngDto>()));
        });

        g.MapPost("/stops-along-route", async (StopsAlongRouteRequest req, IMapProvider maps) =>
        {
            var path = (req.Path ?? new List<LatLngDto>())
                .Select(p => new LatLngPoint(p.Lat, p.Lng))
                .ToList();
            if (path.Count == 0 && req.Origin is not null && req.Destination is not null)
            {
                path =
                [
                    new LatLngPoint(req.Origin.Lat, req.Origin.Lng),
                    new LatLngPoint(req.Destination.Lat, req.Destination.Lng)
                ];
            }

            if (path.Count == 0)
                return Results.BadRequest(new { error = "path or origin/destination required" });

            var stops = await maps.SuggestStopsAlongRouteAsync(path);
            return Results.Ok(stops);
        });

        return g;
    }
}

public record MotorcycleRouteRequest(List<RouteWaypointDto> Waypoints);
public record RouteWaypointDto(string? Name, double Lat, double Lng);
public record LatLngDto(double Lat, double Lng);
public record MotorcycleRouteResponse(
    double DistanceMeters,
    double DurationSeconds,
    string TravelMode,
    string EncodedPolyline,
    List<LatLngDto> Path);
public record StopsAlongRouteRequest(LatLngDto? Origin, LatLngDto? Destination, List<LatLngDto>? Path);
