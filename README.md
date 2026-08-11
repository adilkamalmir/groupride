# GroupRide — Group Ride Operating System

Never lose a rider during a group ride.

## Stack

- **Mobile:** Flutter (iOS-first, Android-ready)
- **API:** ASP.NET Core 8 + SignalR
- **DB:** PostgreSQL 16
- **Maps (MVP):** Google Geocoding + Directions (`two_wheeler` motorbike mode) when `GOOGLE_MAPS_API_KEY` is set; OSM tiles for display; Apple Maps handoff for rejoin

## Quick start (local)

### 1. Database

```bash
# Option A: Docker (when Docker Desktop is running)
docker compose up -d postgres redis

# Option B: Homebrew Postgres (already used if Docker unavailable)
export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"
pg_ctl -D .pgdata -l .pgdata/logfile start   # if using project data dir
```

Connection string (default):

`Host=localhost;Port=5432;Database=groupride;Username=groupride;Password=groupride`

### 2. API

```bash
export PATH="$HOME/.dotnet:$PATH"
dotnet run --project src/GroupRide.Api
```

- Health: http://127.0.0.1:5080/health
- Swagger: http://127.0.0.1:5080/swagger
- SignalR hub: `/hubs/ride`

### 3. Mobile

Flutter was installed to `~/devtools/flutter` (not on system PATH by default).

**Important:** building from `Documents/` fails codesign on recent macOS (`com.apple.provenance`). Use the helper script, which mirrors the app to `~/groupride-ios-build` and runs from there:

```bash
# Backend first
./scripts/start-local.sh

# App on iOS Simulator
export PATH="$HOME/devtools/flutter/bin:/opt/homebrew/bin:$PATH"
./scripts/run-mobile.sh
```

Or manually:

```bash
export PATH="$HOME/devtools/flutter/bin:$HOME/.dotnet:$PATH"
cd ~/groupride-ios-build/mobile   # created by run-mobile.sh
flutter run --dart-define=API_BASE=http://127.0.0.1:5080
```

To persist PATH, add to `~/.zshrc`:

```bash
export PATH="$HOME/devtools/flutter/bin:$HOME/.dotnet:/opt/homebrew/bin:$PATH"
```

### Seed accounts

| Email | Password | Role on demo ride |
|-------|----------|-------------------|
| leader@groupride.local | password123 | Leader |
| sweep@groupride.local | password123 | Sweep |
| rider1@groupride.local | password123 | Rider |
| rider2@groupride.local | password123 | Rider |

Demo invite token: `ottawa-valley-demo`  
Deep link: `groupride://join/ottawa-valley-demo`

## MVP features

1. Ride creation (name, time, meet, destination, stops)
2. Invites via link / QR / share sheet (SMS)
3. Live group map (lead, sweep, riders, status colors)
4. Group split detection (>500m, debounced)
5. Automatic regroup suggestions
6. One-tap Rejoin Group (Apple Maps directions)
7. Roles: Leader / Sweep / Rider
8. Fuel status from bike profiles
9. Emergency “Need Help”
10. Post-ride timeline

## Tests

```bash
dotnet test tests/GroupRide.Cohesion.Tests
cd apps/mobile && flutter test
```

## Field checklist

See [docs/FIELD_CHECKLIST.md](docs/FIELD_CHECKLIST.md).

## Repo layout

```
apps/mobile/                 Flutter client
src/GroupRide.Api/           HTTP + SignalR host
src/GroupRide.Domain/        Entities & contracts
src/GroupRide.Infrastructure/ EF Core, map/push adapters
src/GroupRide.Cohesion/      Split + fuel engines
tests/GroupRide.Cohesion.Tests/
docker-compose.yml
```
