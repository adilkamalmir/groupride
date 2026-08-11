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

        g.MapGet("/autocomplete", async (string q, IMapProvider maps) =>
        {
            if (string.IsNullOrWhiteSpace(q))
                return Results.Ok(Array.Empty<PlaceSuggestion>());
            var suggestions = await maps.AutocompleteAsync(q);
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
