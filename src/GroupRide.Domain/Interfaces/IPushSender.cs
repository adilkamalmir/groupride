namespace GroupRide.Domain.Interfaces;

public interface IPushSender
{
    Task SendToUsersAsync(IEnumerable<Guid> userIds, string title, string body, object? data = null, CancellationToken ct = default);
}
