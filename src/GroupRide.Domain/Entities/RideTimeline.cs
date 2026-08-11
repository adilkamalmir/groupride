namespace GroupRide.Domain.Entities;

public class RideTimeline
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid RideId { get; set; }
    public Ride Ride { get; set; } = null!;

    public double DistanceKm { get; set; }
    public double DurationMinutes { get; set; }
    public string? RoutePolyline { get; set; }
    public string? StopsJson { get; set; }
    public string? AttendanceJson { get; set; }
    public string? PhotoUrlsJson { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
