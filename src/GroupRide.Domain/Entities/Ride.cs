using GroupRide.Domain.Enums;

namespace GroupRide.Domain.Entities;

public class Ride
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;
    public DateTime StartAt { get; set; }
    public RideStatus Status { get; set; } = RideStatus.Draft;
    public Guid CreatedByUserId { get; set; }
    public User CreatedBy { get; set; } = null!;

    public string MeetPointName { get; set; } = string.Empty;
    public double MeetLat { get; set; }
    public double MeetLng { get; set; }

    public string DestinationName { get; set; } = string.Empty;
    public double DestinationLat { get; set; }
    public double DestinationLng { get; set; }

    /// <summary>Encoded polyline or JSON array of [lat,lng] points.</summary>
    public string? RoutePolyline { get; set; }

    public double SplitThresholdMeters { get; set; } = 500;
    public int SplitDurationSeconds { get; set; } = 45;
    public int PingIntervalSeconds { get; set; } = 8;

    public DateTime? StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public ICollection<RideStop> Stops { get; set; } = new List<RideStop>();
    public ICollection<RideMember> Members { get; set; } = new List<RideMember>();
    public ICollection<Invite> Invites { get; set; } = new List<Invite>();
    public ICollection<Alert> Alerts { get; set; } = new List<Alert>();
    public ICollection<Emergency> Emergencies { get; set; } = new List<Emergency>();
    public RideTimeline? Timeline { get; set; }
}
