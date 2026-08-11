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
  docker compose up -d --build
  echo "Waiting for API health..."
  for i in $(seq 1 60); do
    if curl -sf http://127.0.0.1:5080/health >/dev/null; then
      curl -s http://127.0.0.1:5080/health
      echo
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
