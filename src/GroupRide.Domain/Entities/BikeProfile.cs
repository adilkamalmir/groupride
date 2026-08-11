namespace GroupRide.Domain.Entities;

public class BikeProfile
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public User User { get; set; } = null!;

    public string Model { get; set; } = string.Empty;
    public double TankSizeLiters { get; set; }
    public double TypicalRangeKm { get; set; }
    public double? DistanceSinceFillKm { get; set; }
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    public double EstimatedRemainingRangeKm =>
        Math.Max(0, TypicalRangeKm - (DistanceSinceFillKm ?? 0));
}
