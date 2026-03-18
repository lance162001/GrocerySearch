#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$SERVICE_DIR/docker-compose.prod.yml"
ENV_FILE="${ENV_FILE:-$SERVICE_DIR/.env.prod}"

job="${1:-}"
case "$job" in
  scrape)
    compose_service="scraper"
    lock_file="/tmp/grocerysearch-scrape.lock"
    ;;
  logos)
    compose_service="logo_refresh"
    lock_file="/tmp/grocerysearch-logos.lock"
    ;;
  *)
    echo "Usage: $0 {scrape|logos}" >&2
    exit 1
    ;;
esac

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Compose file not found: $COMPOSE_FILE" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Environment file not found: $ENV_FILE" >&2
  echo "Create it from $SERVICE_DIR/.env.prod.example first." >&2
  exit 1
fi

exec 9>"$lock_file"
if ! flock -n 9; then
  echo "Job '$job' already running; skipping." >&2
  exit 0
fi

cd "$SERVICE_DIR"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" run --rm "$compose_service"
