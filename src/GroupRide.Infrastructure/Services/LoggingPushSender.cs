using GroupRide.Domain.Interfaces;
using Microsoft.Extensions.Logging;

namespace GroupRide.Infrastructure.Services;

/// <summary>Logs push notifications locally; replace with APNs/FCM later.</summary>
public class LoggingPushSender : IPushSender
{
    private readonly ILogger<LoggingPushSender> _logger;

    public LoggingPushSender(ILogger<LoggingPushSender> logger) => _logger = logger;

    public Task SendToUsersAsync(IEnumerable<Guid> userIds, string title, string body, object? data = null, CancellationToken ct = default)
    {
        _logger.LogInformation("PUSH → [{Users}] {Title}: {Body}", string.Join(",", userIds), title, body);
        return Task.CompletedTask;
    }
}
