namespace GroupRide.Domain.Entities;

public class LocationPing
{
    public long Id { get; set; }
    public Guid RideId { get; set; }
    public Guid UserId { get; set; }
    public double Lat { get; set; }
    public double Lng { get; set; }
    public double? SpeedMps { get; set; }
    public double? Heading { get; set; }
    public double? AccuracyMeters { get; set; }
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
}
