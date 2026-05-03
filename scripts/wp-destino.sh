#!/usr/bin/env bash
# WP-CLI wrapper for the destino site.
#   ./scripts/wp-destino.sh plugin list
#   ./scripts/wp-destino.sh option get siteurl
set -euo pipefail
cd "$(dirname "$0")/../docker"
exec docker compose run --rm wpcli-destino wp "$@"
