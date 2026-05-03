#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# bootstrap.sh — idempotent local-environment installer.
#
# Runs doctor.sh, generates .env from .env.example with random passwords if
# missing, builds the dev image, brings the stack up, waits for healthchecks,
# and runs `wp core install` on both sites. Safe to re-run.
# -----------------------------------------------------------------------------

set -euo pipefail

readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[0;33m'
readonly BLUE=$'\033[0;34m'
readonly BOLD=$'\033[1m'
readonly RESET=$'\033[0m'

step()  { printf '\n%s==>%s %s\n'        "$BLUE"   "$RESET" "$1"; }
ok()    { printf '%s[ OK ]%s %s\n'        "$GREEN"  "$RESET" "$1"; }
warn()  { printf '%s[WARN]%s %s\n'        "$YELLOW" "$RESET" "$1"; }
fail()  { printf '%s[FAIL]%s %s\n'        "$RED"    "$RESET" "$1" >&2; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKER_DIR="${REPO_ROOT}/docker"
ENV_FILE="${REPO_ROOT}/.env"
ENV_EXAMPLE="${REPO_ROOT}/.env.example"

# -----------------------------------------------------------------------------
# 1. Run doctor.sh — abort on FAIL.
# -----------------------------------------------------------------------------
step "Running pre-flight diagnostics"
if ! "${REPO_ROOT}/scripts/doctor.sh"; then
    fail "doctor.sh reported failures. Fix them and re-run bootstrap."
    exit 1
fi

# -----------------------------------------------------------------------------
# 2. Generate .env if missing, filling in random passwords.
# -----------------------------------------------------------------------------
step "Ensuring .env exists with secure passwords"

random_hex() { openssl rand -hex 16; }

if [[ ! -f "$ENV_FILE" ]]; then
    if [[ ! -f "$ENV_EXAMPLE" ]]; then
        fail ".env.example is missing — cannot generate .env."
        exit 1
    fi
    cp "$ENV_EXAMPLE" "$ENV_FILE"

    # Fill empty *_PASSWORD variables with random hex strings.
    tmp_env="$(mktemp)"
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^([A-Z_]+_PASSWORD)=$ ]]; then
            printf '%s=%s\n' "${BASH_REMATCH[1]}" "$(random_hex)" >> "$tmp_env"
        else
            printf '%s\n' "$line" >> "$tmp_env"
        fi
    done < "$ENV_FILE"
    mv "$tmp_env" "$ENV_FILE"
    chmod 600 "$ENV_FILE"

    ok "Generated .env with random DB passwords"
else
    ok ".env already exists — leaving it alone"
fi

# Load env vars for the rest of the script.
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

# -----------------------------------------------------------------------------
# 3 + 4. Build images and start the stack.
# -----------------------------------------------------------------------------
step "Building the WordPress dev image"
( cd "$DOCKER_DIR" && docker compose build )
ok "Image build complete"

step "Starting the stack (docker compose up -d)"
( cd "$DOCKER_DIR" && docker compose up -d )
ok "Containers started"

# -----------------------------------------------------------------------------
# 5. Wait for DB and WP healthchecks.
# -----------------------------------------------------------------------------
wait_healthy() {
    local service="$1"
    local timeout="${2:-120}"
    local container_id elapsed=0 status

    step "Waiting for ${service} to become healthy (timeout ${timeout}s)"
    container_id="$( cd "$DOCKER_DIR" && docker compose ps -q "$service" )"
    if [[ -z "$container_id" ]]; then
        fail "${service} is not running — check \`docker compose ps\`."
        return 1
    fi

    while (( elapsed < timeout )); do
        status="$(docker inspect -f '{{.State.Health.Status}}' "$container_id" 2>/dev/null || echo unknown)"
        case "$status" in
            healthy)   ok "${service} is healthy"; return 0 ;;
            unhealthy) fail "${service} reported unhealthy"; return 1 ;;
        esac
        sleep 3
        elapsed=$((elapsed + 3))
    done

    fail "${service} did not become healthy within ${timeout}s (last status: ${status:-unknown})"
    return 1
}

wait_healthy db-origen   120
wait_healthy db-destino  120
wait_healthy wp-origen   180
wait_healthy wp-destino  180

# -----------------------------------------------------------------------------
# 6. Verify the routing actually works.
# -----------------------------------------------------------------------------
verify_routing() {
    local domain="$1"
    local url="http://${domain}:${HTTP_PORT}"
    local attempt=0 max=20

    step "Verifying ${url}"
    while (( attempt < max )); do
        if curl -fsS --max-time 5 -o /dev/null "$url"; then
            ok "${url} answers"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    warn "${url} did not answer after ${max} attempts — proceed and check Traefik dashboard."
    return 1
}

verify_routing "$ORIGEN_DOMAIN"
verify_routing "$DESTINO_DOMAIN"

# -----------------------------------------------------------------------------
# 7. Install WordPress on both sites with WP-CLI.
# -----------------------------------------------------------------------------
wp_origen()  { ( cd "$DOCKER_DIR" && docker compose run --rm -T wpcli-origen  "$@" ); }
wp_destino() { ( cd "$DOCKER_DIR" && docker compose run --rm -T wpcli-destino "$@" ); }

install_site() {
    local label="$1" runner="$2" domain="$3" title="$4"

    step "Installing WordPress on ${label} (${domain})"

    if "$runner" wp core is-installed >/dev/null 2>&1; then
        ok "${label}: WordPress is already installed"
        return 0
    fi

    "$runner" wp core install \
        --url="http://${domain}:${HTTP_PORT}" \
        --title="${title}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email
    ok "${label}: wp core install OK"
}

install_site "origen"  wp_origen  "$ORIGEN_DOMAIN"  "Volcán — Origen"
install_site "destino" wp_destino "$DESTINO_DOMAIN" "Volcán — Destino"

# Optional multisite on origen.
if [[ "${ENABLE_MULTISITE_ORIGEN,,}" == "true" ]]; then
    step "Enabling multisite on origen"
    if wp_origen wp core is-installed --network >/dev/null 2>&1; then
        ok "origen: multisite already enabled"
    else
        wp_origen wp core multisite-convert --title="Volcán Network" || \
            warn "wp core multisite-convert failed — review manually."
    fi
fi

# -----------------------------------------------------------------------------
# 8. Activate the plugin (best-effort — may not exist yet).
# -----------------------------------------------------------------------------
activate_plugin() {
    local label="$1" runner="$2"
    if "$runner" wp plugin is-installed volcan-migration >/dev/null 2>&1; then
        if "$runner" wp plugin activate volcan-migration >/dev/null 2>&1; then
            ok "${label}: volcan-migration plugin activated"
        else
            warn "${label}: could not activate volcan-migration (likely no main file yet)"
        fi
    else
        warn "${label}: volcan-migration plugin not detected — expected before the bootstrap."
    fi
}

step "Activating the volcan-migration plugin (best-effort)"
activate_plugin "origen"  wp_origen
activate_plugin "destino" wp_destino

# -----------------------------------------------------------------------------
# 9. Summary.
# -----------------------------------------------------------------------------
cat <<EOF

${BOLD}Volcán Migration — environment is up.${RESET}

  ${BOLD}Origen${RESET}    http://${ORIGEN_DOMAIN}:${HTTP_PORT}/wp-admin
  ${BOLD}Destino${RESET}   http://${DESTINO_DOMAIN}:${HTTP_PORT}/wp-admin
  ${BOLD}phpMyAdmin${RESET} http://${PMA_DOMAIN}:${HTTP_PORT}
  ${BOLD}Mailpit${RESET}    http://${MAIL_DOMAIN}:${HTTP_PORT}
  ${BOLD}Traefik${RESET}    http://${TRAEFIK_DASHBOARD_DOMAIN}:${TRAEFIK_DASHBOARD_PORT}/dashboard/

  Admin user:     ${WP_ADMIN_USER}
  Admin password: ${WP_ADMIN_PASSWORD}
  Admin email:    ${WP_ADMIN_EMAIL}

Next steps:
  ./scripts/wp-origen.sh plugin list
  ./scripts/seed-origen.sh        # populate origen with sample content
  ./scripts/logs.sh wp-origen     # tail logs
  ./scripts/reset.sh              # tear down and remove volumes

EOF
