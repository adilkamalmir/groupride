using GroupRide.Domain.Enums;

namespace GroupRide.Domain.Entities;

public class Emergency
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid RideId { get; set; }
    public Ride Ride { get; set; } = null!;
    public Guid UserId { get; set; }
    public User User { get; set; } = null!;
    public EmergencyType Type { get; set; }
    public double Lat { get; set; }
    public double Lng { get; set; }
    public string? Notes { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public Guid? AcknowledgedByUserId { get; set; }
    public DateTime? AcknowledgedAt { get; set; }
    public bool IsResolved { get; set; }
}
