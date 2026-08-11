#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.dotnet:/opt/homebrew/opt/postgresql@16/bin:${HOME}/devtools/flutter/bin:${PATH}"

cd "$ROOT"

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  echo "Starting backend via Docker Compose..."
  if [[ -n "${GOOGLE_MAPS_API_KEY:-}" ]]; then
    echo "Google Maps API key detected — geocoding + motorcycle routing enabled."
  else
    echo "No GOOGLE_MAPS_API_KEY — using local map fallback (known Ottawa places)."
  fi
  docker compose up -d --build --force-recreate
  echo "Waiting for API health..."
  for i in $(seq 1 60); do
    if curl -sf http://127.0.0.1:5080/health >/dev/null; then
      curl -s http://127.0.0.1:5080/health
      echo
      echo "Checking demo + nearby endpoints..."
      # Unauthenticated probe: 401 means route exists; 404 means image is stale.
      code_demo=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:5080/api/rides/00000000-0000-0000-0000-000000000001/demo || true)
      code_near=$(curl -s -o /dev/null -w '%{http_code}' 'http://127.0.0.1:5080/api/maps/nearby?lat=45.3&lng=-75.9' || true)
      echo "  POST /api/rides/.../demo → HTTP $code_demo (expect 401/403/400, not 404)"
      echo "  GET  /api/maps/nearby     → HTTP $code_near (expect 200, not 404)"
      docker compose ps
      exit 0
    fi
    sleep 2
  done
  echo "API failed to become healthy. Recent logs:"
  docker compose logs api --tail 80
  exit 1
fi

if [[ -d "$ROOT/.pgdata" ]]; then
  echo "Docker unavailable — falling back to local Postgres (.pgdata)..."
  if ! pg_isready -q 2>/dev/null; then
    pg_ctl -D "$ROOT/.pgdata" -l "$ROOT/.pgdata/logfile" start
  fi
  echo "Starting GroupRide API on http://0.0.0.0:5080 ..."
  exec dotnet run --project src/GroupRide.Api
fi

echo "Neither Docker nor .pgdata is available."
exit 1
