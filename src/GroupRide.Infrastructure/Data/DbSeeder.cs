using GroupRide.Domain.Entities;
using GroupRide.Domain.Enums;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace GroupRide.Infrastructure.Data;

public class DbSeeder : IHostedService
{
    private readonly IServiceProvider _sp;
    private readonly ILogger<DbSeeder> _logger;

    public DbSeeder(IServiceProvider sp, ILogger<DbSeeder> logger)
    {
        _sp = sp;
        _logger = logger;
    }

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        using var scope = _sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.MigrateAsync(cancellationToken);

        if (await db.Users.AnyAsync(cancellationToken))
        {
            _logger.LogInformation("Database already seeded");
            return;
        }

        _logger.LogInformation("Seeding sample Ottawa Valley ride...");

        var leader = new User
        {
            Email = "leader@groupride.local",
            DisplayName = "Alex Lead",
            PasswordHash = BCrypt.Net.BCrypt.HashPassword("password123")
        };
        var sweep = new User
        {
            Email = "sweep@groupride.local",
            DisplayName = "Sam Sweep",
            PasswordHash = BCrypt.Net.BCrypt.HashPassword("password123")
        };
        var rider1 = new User
        {
            Email = "rider1@groupride.local",
            DisplayName = "Jordan Rider",
            PasswordHash = BCrypt.Net.BCrypt.HashPassword("password123")
        };
        var rider2 = new User
        {
            Email = "rider2@groupride.local",
            DisplayName = "Casey Rider",
            PasswordHash = BCrypt.Net.BCrypt.HashPassword("password123")
        };

        db.Users.AddRange(leader, sweep, rider1, rider2);

        db.BikeProfiles.AddRange(
            new BikeProfile { UserId = leader.Id, Model = "Honda CB500X", TankSizeLiters = 17.7, TypicalRangeKm = 400, DistanceSinceFillKm = 120 },
            new BikeProfile { UserId = sweep.Id, Model = "Harley Street Bob", TankSizeLiters = 13.2, TypicalRangeKm = 250, DistanceSinceFillKm = 180 },
            new BikeProfile { UserId = rider1.Id, Model = "Yamaha MT-07", TankSizeLiters = 14, TypicalRangeKm = 300, DistanceSinceFillKm = 80 },
            new BikeProfile { UserId = rider2.Id, Model = "BMW F850GS", TankSizeLiters = 15, TypicalRangeKm = 350, DistanceSinceFillKm = 200 }
        );

        var ride = new Ride
        {
            Name = "Sunday Ottawa Valley Ride",
            StartAt = DateTime.UtcNow.Date.AddDays(GetDaysUntilSunday()).AddHours(14), // 10am ET approx
            Status = RideStatus.Open,
            CreatedByUserId = leader.Id,
            MeetPointName = "Tim Hortons Kanata",
            MeetLat = 45.3001,
            MeetLng = -75.9105,
            DestinationName = "Calabogie",
            DestinationLat = 45.3008,
            DestinationLng = -76.7175,
            RoutePolyline = "[{\"lat\":45.3001,\"lng\":-75.9105},{\"lat\":45.4747,\"lng\":-76.6831},{\"lat\":45.3008,\"lng\":-76.7175}]"
        };

        ride.Stops.Add(new RideStop { Name = "Renfrew", Kind = "fuel", Lat = 45.4747, Lng = -76.6831, SortOrder = 1, DistanceFromStartKm = 75 });
        ride.Stops.Add(new RideStop { Name = "Calabogie", Kind = "lunch", Lat = 45.3008, Lng = -76.7175, SortOrder = 2, DistanceFromStartKm = 110 });

        ride.Members.Add(new RideMember { UserId = leader.Id, Role = RideRole.Leader, InviteStatus = InviteStatus.Accepted });
        ride.Members.Add(new RideMember { UserId = sweep.Id, Role = RideRole.Sweep, InviteStatus = InviteStatus.Accepted });
        ride.Members.Add(new RideMember { UserId = rider1.Id, Role = RideRole.Rider, InviteStatus = InviteStatus.Accepted });
        ride.Members.Add(new RideMember { UserId = rider2.Id, Role = RideRole.Rider, InviteStatus = InviteStatus.Accepted });

        var invite = new Invite
        {
            RideId = ride.Id,
            Token = "ottawa-valley-demo",
            ExpiresAt = DateTime.UtcNow.AddDays(30)
        };

        db.Rides.Add(ride);
        // Fix invite ride ref after ride id assigned
        invite.RideId = ride.Id;
        ride.Invites.Add(invite);

        await db.SaveChangesAsync(cancellationToken);
        _logger.LogInformation("Seeded users (password: password123) and ride {RideName} invite token={Token}", ride.Name, invite.Token);
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    private static int GetDaysUntilSunday()
    {
        var today = DateTime.UtcNow.DayOfWeek;
        var days = ((int)DayOfWeek.Sunday - (int)today + 7) % 7;
        return days == 0 ? 7 : days;
    }
}
