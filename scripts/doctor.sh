#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# doctor.sh — pre-flight diagnostic for the Volcán Migration dev environment.
#
# Verifies Docker, port availability, and WSL2-specific gotchas (paths on
# /mnt/c, listeners on the Windows side that would clash with port 8080).
# Exits non-zero on FAIL so bootstrap.sh can abort cleanly.
# -----------------------------------------------------------------------------

set -euo pipefail

readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[0;33m'
readonly BLUE=$'\033[0;34m'
readonly DIM=$'\033[2m'
readonly RESET=$'\033[0m'

FAIL_COUNT=0
WARN_COUNT=0

ok()    { printf '%s[ OK ]%s %s\n'   "$GREEN"  "$RESET" "$1"; }
fail()  { printf '%s[FAIL]%s %s\n'   "$RED"    "$RESET" "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
warn()  { printf '%s[WARN]%s %s\n'   "$YELLOW" "$RESET" "$1"; WARN_COUNT=$((WARN_COUNT + 1)); }
info()  { printf '%s[INFO]%s %s\n'   "$BLUE"   "$RESET" "$1"; }
note()  { printf '       %s%s%s\n'    "$DIM"   "$1"     "$RESET"; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
ENV_EXAMPLE="${REPO_ROOT}/.env.example"

# Read HTTP_PORT / TRAEFIK_DASHBOARD_PORT from .env (or fall back to defaults).
HTTP_PORT=8080
TRAEFIK_DASHBOARD_PORT=8081
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    set -a; source "$ENV_FILE"; set +a
elif [[ -f "$ENV_EXAMPLE" ]]; then
    # shellcheck disable=SC1090
    set -a; source "$ENV_EXAMPLE"; set +a
fi

ORIGEN_DOMAIN="${ORIGEN_DOMAIN:-origen.volcan.localhost}"

printf '\n%s== Volcán Migration — environment doctor ==%s\n\n' "$BLUE" "$RESET"

# --- 1. Docker daemon ---------------------------------------------------------
if docker info >/dev/null 2>&1; then
    ok "Docker daemon is reachable"
else
    fail "Docker daemon is not reachable. Start Docker Desktop and ensure WSL integration is on for this distro."
fi

# --- 2. Docker Compose v2 -----------------------------------------------------
if docker compose version >/dev/null 2>&1; then
    compose_version="$(docker compose version --short 2>/dev/null || echo unknown)"
    ok "Docker Compose v2 available (${compose_version})"
else
    fail "Docker Compose v2 not found. Use Docker Desktop ≥ 20.10 with the integrated 'docker compose' subcommand."
fi

# --- 3 & 4. Port availability -------------------------------------------------
check_port() {
    local port="$1"
    local label="$2"
    local listener=""

    # WSL2-side listeners. ss may not have permission to read the program
    # column without root; we still get the listening sockets.
    if command -v ss >/dev/null 2>&1; then
        listener="$(ss -tln 2>/dev/null | awk -v p=":${port}$" '$4 ~ p {print $4; exit}')"
    fi

    if [[ -n "$listener" ]]; then
        fail "Port ${port} (${label}) is already bound inside WSL2: ${listener}"
        note "Run \`ss -tlnp\` to see the program; either stop it or change ${label} in .env."
        return
    fi

    # Cross-check against Windows-side listeners (Herd, IIS, etc.) — those don't
    # show up in WSL's ss but DO answer TCP on localhost via the WSL2 network.
    if command -v bash >/dev/null 2>&1 && timeout 1 bash -c "</dev/tcp/127.0.0.1/${port}" >/dev/null 2>&1; then
        fail "Port ${port} (${label}) answers on 127.0.0.1 — likely Herd/IIS/Apache on Windows."
        note "Stop the offender or change ${label} in .env (default: ${port})."
        return
    fi

    ok "Port ${port} (${label}) is free"
}

check_port "$HTTP_PORT" "HTTP_PORT"
check_port "$TRAEFIK_DASHBOARD_PORT" "TRAEFIK_DASHBOARD_PORT"

# --- 5. WSL2 detection --------------------------------------------------------
if grep -qi microsoft /proc/version 2>/dev/null; then
    info "Running inside WSL2 (kernel: $(uname -r))"
else
    info "Not running inside WSL2 — that's fine if Docker Desktop is local."
fi

# --- 6. Repo location (warn on /mnt/c) ----------------------------------------
case "$REPO_ROOT" in
    /mnt/*)
        warn "Repository lives on a Windows-mounted drive (${REPO_ROOT})."
        note "Move it to ~/proyectos/... inside WSL2 for 10–50× better I/O performance."
        ;;
    *)
        ok "Repository is on the WSL2 native filesystem (${REPO_ROOT})"
        ;;
esac

# --- 7. DNS resolution for origen.volcan.localhost ----------------------------
# Browsers resolve *.localhost on their own, but getent/curl-from-WSL may not.
# This is informational only.
if getent hosts "$ORIGEN_DOMAIN" >/dev/null 2>&1; then
    ok "${ORIGEN_DOMAIN} resolves locally via NSS"
else
    info "${ORIGEN_DOMAIN} does not resolve via getent — this is expected on Linux."
    note "Browsers (Chrome/Firefox/Edge) handle *.localhost natively per RFC 6761."
fi

# --- 8. Anything already answering on the target URL? -------------------------
target_url="http://${ORIGEN_DOMAIN}:${HTTP_PORT}"
if command -v curl >/dev/null 2>&1; then
    if curl -fsS --max-time 2 -o /dev/null "$target_url" 2>/dev/null; then
        warn "${target_url} is already answering. Another container or process may be running."
        note "Run \`./scripts/reset.sh\` if it's a stale Volcán stack."
    else
        ok "Nothing is currently answering on ${target_url}"
    fi
fi

# --- Summary ------------------------------------------------------------------
printf '\n'
if [[ "$FAIL_COUNT" -gt 0 ]]; then
    printf '%sDoctor failed:%s %d FAIL, %d WARN\n\n' "$RED" "$RESET" "$FAIL_COUNT" "$WARN_COUNT"
    exit 1
fi

if [[ "$WARN_COUNT" -gt 0 ]]; then
    printf '%sDoctor passed with warnings:%s %d WARN\n\n' "$YELLOW" "$RESET" "$WARN_COUNT"
else
    printf '%sDoctor passed cleanly.%s\n\n' "$GREEN" "$RESET"
fi
exit 0
