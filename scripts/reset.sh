#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# reset.sh — tear down the dev stack and remove all named volumes.
#
# Usage:
#   ./scripts/reset.sh                # confirm, then docker compose down -v + rm .env
#   ./scripts/reset.sh --keep-env     # keep .env (just down -v)
#   ./scripts/reset.sh --yes          # skip the confirmation prompt
# -----------------------------------------------------------------------------

set -euo pipefail

readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[0;33m'
readonly BLUE=$'\033[0;34m'
readonly RESET=$'\033[0m'

step() { printf '\n%s==>%s %s\n' "$BLUE" "$RESET" "$1"; }
ok()   { printf '%s[ OK ]%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$1"; }
fail() { printf '%s[FAIL]%s %s\n' "$RED"   "$RESET" "$1" >&2; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKER_DIR="${REPO_ROOT}/docker"
ENV_FILE="${REPO_ROOT}/.env"

KEEP_ENV=0
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        --keep-env) KEEP_ENV=1 ;;
        --yes|-y)   ASSUME_YES=1 ;;
        --help|-h)
            sed -n '4,12p' "$0"
            exit 0
            ;;
        *) fail "Unknown argument: $arg"; exit 2 ;;
    esac
done

if [[ "$ASSUME_YES" -ne 1 ]]; then
    printf '%sThis will stop containers and DELETE all named volumes' "$YELLOW"
    if [[ "$KEEP_ENV" -eq 0 ]]; then
        printf ' AND remove .env'
    fi
    printf '.%s\n' "$RESET"
    read -r -p "Proceed? [y/N] " reply
    case "$reply" in
        [yY]|[yY][eE][sS]) ;;
        *) printf 'Aborted.\n'; exit 0 ;;
    esac
fi

step "docker compose down -v"
( cd "$DOCKER_DIR" && docker compose --profile cli down -v --remove-orphans )
ok "Containers and volumes removed"

if [[ "$KEEP_ENV" -eq 1 ]]; then
    warn "Keeping .env at user request"
elif [[ -f "$ENV_FILE" ]]; then
    rm -f "$ENV_FILE"
    ok "Removed .env"
fi

printf '\n%sReset complete. Run ./scripts/bootstrap.sh to rebuild.%s\n\n' "$GREEN" "$RESET"
