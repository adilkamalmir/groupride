using GroupRide.Domain.Enums;

namespace GroupRide.Domain.Entities;

public class RideMember
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid RideId { get; set; }
    public Ride Ride { get; set; } = null!;
    public Guid UserId { get; set; }
    public User User { get; set; } = null!;

    public RideRole Role { get; set; } = RideRole.Rider;
    public InviteStatus InviteStatus { get; set; } = InviteStatus.Accepted;
    public RiderStatus Status { get; set; } = RiderStatus.Riding;
    public bool Attended { get; set; }
    public DateTime JoinedAt { get; set; } = DateTime.UtcNow;

    public double? LastLat { get; set; }
    public double? LastLng { get; set; }
    public double? LastSpeedMps { get; set; }
    public double? LastHeading { get; set; }
    public DateTime? LastLocationAt { get; set; }
    public double DistanceSinceStartKm { get; set; }
}
