#!/usr/bin/env bash
# Tail container logs.
#   ./scripts/logs.sh             # tail every service
#   ./scripts/logs.sh wp-origen   # tail a single service
set -euo pipefail
cd "$(dirname "$0")/../docker"
exec docker compose logs -f --tail=100 "$@"
