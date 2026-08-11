namespace GroupRide.Domain.Entities;

public class RideStop
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid RideId { get; set; }
    public Ride Ride { get; set; } = null!;

    public string Name { get; set; } = string.Empty;
    public string? Kind { get; set; } // fuel, lunch, rest, parking
    public double Lat { get; set; }
    public double Lng { get; set; }
    public int SortOrder { get; set; }
    public double? DistanceFromStartKm { get; set; }
}
