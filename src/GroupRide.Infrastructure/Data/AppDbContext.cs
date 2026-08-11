using GroupRide.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace GroupRide.Infrastructure.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<User> Users => Set<User>();
    public DbSet<BikeProfile> BikeProfiles => Set<BikeProfile>();
    public DbSet<Ride> Rides => Set<Ride>();
    public DbSet<RideStop> RideStops => Set<RideStop>();
    public DbSet<RideMember> RideMembers => Set<RideMember>();
    public DbSet<Invite> Invites => Set<Invite>();
    public DbSet<LocationPing> LocationPings => Set<LocationPing>();
    public DbSet<Alert> Alerts => Set<Alert>();
    public DbSet<Emergency> Emergencies => Set<Emergency>();
    public DbSet<RideTimeline> RideTimelines => Set<RideTimeline>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<User>(e =>
        {
            e.HasIndex(x => x.Email).IsUnique();
            e.Property(x => x.Email).HasMaxLength(256);
            e.Property(x => x.DisplayName).HasMaxLength(128);
        });

        modelBuilder.Entity<BikeProfile>(e =>
        {
            e.HasOne(x => x.User).WithOne(x => x.Bike).HasForeignKey<BikeProfile>(x => x.UserId);
        });

        modelBuilder.Entity<Ride>(e =>
        {
            e.Property(x => x.Name).HasMaxLength(200);
            e.HasOne(x => x.CreatedBy).WithMany().HasForeignKey(x => x.CreatedByUserId);
            e.HasOne(x => x.Timeline).WithOne(x => x.Ride).HasForeignKey<RideTimeline>(x => x.RideId);
        });

        modelBuilder.Entity<RideMember>(e =>
        {
            e.HasIndex(x => new { x.RideId, x.UserId }).IsUnique();
            e.HasOne(x => x.Ride).WithMany(x => x.Members).HasForeignKey(x => x.RideId);
            e.HasOne(x => x.User).WithMany(x => x.Memberships).HasForeignKey(x => x.UserId);
        });

        modelBuilder.Entity<Invite>(e =>
        {
            e.HasIndex(x => x.Token).IsUnique();
            e.Property(x => x.Token).HasMaxLength(64);
        });

        modelBuilder.Entity<LocationPing>(e =>
        {
            e.HasIndex(x => new { x.RideId, x.Timestamp });
            e.HasIndex(x => new { x.RideId, x.UserId, x.Timestamp });
        });

        modelBuilder.Entity<Alert>(e =>
        {
            e.HasIndex(x => new { x.RideId, x.CreatedAt });
        });
    }
}
