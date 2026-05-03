#!/usr/bin/env bash
# WP-CLI wrapper for the origen site.
#   ./scripts/wp-origen.sh plugin list
#   ./scripts/wp-origen.sh user create alice alice@example.com --role=editor
set -euo pipefail
cd "$(dirname "$0")/../docker"
exec docker compose run --rm wpcli-origen wp "$@"
