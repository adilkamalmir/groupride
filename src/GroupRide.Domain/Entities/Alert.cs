using GroupRide.Domain.Enums;

namespace GroupRide.Domain.Entities;

public class Alert
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid RideId { get; set; }
    public Ride Ride { get; set; } = null!;
    public AlertType Type { get; set; }
    public string Message { get; set; } = string.Empty;
    public string? PayloadJson { get; set; }
    /// <summary>JSON array of user IDs who should receive this alert. Null/empty = all ride members.</summary>
    public string? RecipientsJson { get; set; }
    public Guid? RelatedUserId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
