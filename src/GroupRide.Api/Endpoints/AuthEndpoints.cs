using GroupRide.Api.Auth;
using GroupRide.Api.Dtos;
using GroupRide.Domain.Entities;
using GroupRide.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace GroupRide.Api.Endpoints;

public static class AuthEndpoints
{
    public static RouteGroupBuilder MapAuthEndpoints(this WebApplication app)
    {
        var g = app.MapGroup("/api/auth").WithTags("Auth");

        g.MapPost("/register", async (RegisterRequest req, AppDbContext db, JwtTokenService jwt) =>
        {
            var email = req.Email.Trim().ToLowerInvariant();
            if (await db.Users.AnyAsync(u => u.Email == email))
                return Results.Conflict(new { error = "Email already registered" });

            var user = new User
            {
                Email = email,
                DisplayName = req.DisplayName.Trim(),
                Phone = req.Phone,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.Password)
            };
            db.Users.Add(user);
            await db.SaveChangesAsync();

            var token = jwt.CreateToken(user);
            return Results.Ok(new AuthResponse(token, user.Id, user.Email, user.DisplayName));
        });

        g.MapPost("/login", async (LoginRequest req, AppDbContext db, JwtTokenService jwt) =>
        {
            var email = req.Email.Trim().ToLowerInvariant();
            var user = await db.Users.FirstOrDefaultAsync(u => u.Email == email);
            if (user is null || !BCrypt.Net.BCrypt.Verify(req.Password, user.PasswordHash))
                return Results.Unauthorized();

            return Results.Ok(new AuthResponse(jwt.CreateToken(user), user.Id, user.Email, user.DisplayName));
        });

        return g;
    }
}
