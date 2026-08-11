using System.Security.Claims;
using GroupRide.Api.Auth;
using GroupRide.Api.Dtos;
using GroupRide.Domain.Entities;
using GroupRide.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace GroupRide.Api.Endpoints;

public static class ProfileEndpoints
{
    public static RouteGroupBuilder MapProfileEndpoints(this WebApplication app)
    {
        var g = app.MapGroup("/api/me").WithTags("Profile").RequireAuthorization();

        g.MapGet("/", async (ClaimsPrincipal principal, AppDbContext db) =>
        {
            var userId = principal.GetUserId();
            var user = await db.Users.Include(u => u.Bike).FirstOrDefaultAsync(u => u.Id == userId);
            if (user is null) return Results.NotFound();
            return Results.Ok(ToDto(user));
        });

        g.MapPut("/bike", async (UpdateBikeRequest req, ClaimsPrincipal principal, AppDbContext db) =>
        {
            var userId = principal.GetUserId();
            var bike = await db.BikeProfiles.FirstOrDefaultAsync(b => b.UserId == userId);
            if (bike is null)
            {
                bike = new BikeProfile { UserId = userId };
                db.BikeProfiles.Add(bike);
            }

            bike.Model = req.Model;
            bike.TankSizeLiters = req.TankSizeLiters;
            bike.TypicalRangeKm = req.TypicalRangeKm;
            bike.DistanceSinceFillKm = req.DistanceSinceFillKm;
            bike.UpdatedAt = DateTime.UtcNow;
            await db.SaveChangesAsync();

            var user = await db.Users.Include(u => u.Bike).FirstAsync(u => u.Id == userId);
            return Results.Ok(ToDto(user));
        });

        return g;
    }

    private static UserProfileDto ToDto(User u) => new(
        u.Id, u.Email, u.DisplayName, u.Phone,
        u.Bike is null ? null : new BikeProfileDto(
            u.Bike.Model, u.Bike.TankSizeLiters, u.Bike.TypicalRangeKm, u.Bike.DistanceSinceFillKm));
}
