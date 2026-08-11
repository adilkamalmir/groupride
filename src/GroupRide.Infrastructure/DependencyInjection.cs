using GroupRide.Domain.Interfaces;
using GroupRide.Infrastructure.Data;
using GroupRide.Infrastructure.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using StackExchange.Redis;

namespace GroupRide.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration config)
    {
        var conn = config.GetConnectionString("Default")
                   ?? "Host=localhost;Port=5432;Database=groupride;Username=groupride;Password=groupride";

        services.AddDbContext<AppDbContext>(opt =>
            opt.UseNpgsql(conn));

        services.AddHttpClient("GoogleMaps");
        var googleKey = config["GoogleMaps:ApiKey"] ?? config["GOOGLE_MAPS_API_KEY"];
        if (!string.IsNullOrWhiteSpace(googleKey))
        {
            services.AddSingleton<IMapProvider>(sp =>
            {
                var http = sp.GetRequiredService<IHttpClientFactory>().CreateClient("GoogleMaps");
                var logger = sp.GetRequiredService<ILogger<GoogleMapsProvider>>();
                return new GoogleMapsProvider(http, config, logger);
            });
        }
        else
        {
            services.AddSingleton<IMapProvider, LocalMapProvider>();
        }

        services.AddSingleton<IPushSender, LoggingPushSender>();

        var redisConn = config.GetConnectionString("Redis") ?? "localhost:6379";
        var redisOptions = ConfigurationOptions.Parse(redisConn);
        redisOptions.AbortOnConnectFail = false;
        var mux = ConnectionMultiplexer.Connect(redisOptions);
        services.AddSingleton<IConnectionMultiplexer>(mux);
        services.AddSingleton<ILocationStore, RedisLocationStore>();
        // Keep in-memory available for tests / fallback injection if needed
        services.AddSingleton<InMemoryLocationStore>();

        services.AddHostedService<DbSeeder>();
        services.AddHostedService<SchemaPatcher>();

        return services;
    }
}

/// <summary>Applies lightweight additive schema patches without a full migration cycle.</summary>
public class SchemaPatcher : Microsoft.Extensions.Hosting.IHostedService
{
    private readonly IServiceProvider _sp;
    private readonly ILogger<SchemaPatcher> _logger;

    public SchemaPatcher(IServiceProvider sp, ILogger<SchemaPatcher> logger)
    {
        _sp = sp;
        _logger = logger;
    }

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        using var scope = _sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        try
        {
            await db.Database.ExecuteSqlRawAsync(
                """ALTER TABLE "Alerts" ADD COLUMN IF NOT EXISTS "RecipientsJson" text;""",
                cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Schema patch for Alerts.RecipientsJson skipped");
        }
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
