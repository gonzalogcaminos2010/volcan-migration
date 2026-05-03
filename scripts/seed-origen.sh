#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# seed-origen.sh — populate the origen site with realistic test data.
#
# Generates posts, pages, users, attachments (from picsum.photos), installs
# a couple of canonical plugins, and stores a deeply-nested serialized option
# so the URL rewriter can be exercised against it.
# -----------------------------------------------------------------------------

set -euo pipefail

readonly GREEN=$'\033[0;32m'
readonly BLUE=$'\033[0;34m'
readonly YELLOW=$'\033[0;33m'
readonly RESET=$'\033[0m'

step() { printf '\n%s==>%s %s\n' "$BLUE" "$RESET" "$1"; }
ok()   { printf '%s[ OK ]%s %s\n' "$GREEN" "$RESET" "$1"; }
warn() { printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$1"; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WP="${REPO_ROOT}/scripts/wp-origen.sh"

step "Generating 20 posts"
"$WP" post generate --count=20 --post_status=publish

step "Generating 10 pages"
"$WP" post generate --count=10 --post_type=page --post_status=publish

step "Generating 5 users"
for i in 1 2 3 4 5; do
    user="seed_user_${i}"
    if "$WP" user get "$user" >/dev/null 2>&1; then
        warn "User ${user} already exists — skipping"
    else
        "$WP" user create "$user" "${user}@volcan.localhost" \
            --role=author \
            --user_pass="seedpass${i}" \
            --display_name="Seed User ${i}"
    fi
done

step "Importing 50 sample images from picsum.photos"
for i in $(seq 1 50); do
    url="https://picsum.photos/seed/volcan-${i}/800/600.jpg"
    "$WP" media import "$url" \
        --title="Volcán seed image ${i}" \
        --alt="Volcán seed image ${i}" \
        --porcelain >/dev/null \
        || warn "media import failed for image ${i} (continuing)"
done
ok "Image import loop finished"

step "Installing baseline plugins"
"$WP" plugin install hello-dolly  --activate || warn "hello-dolly install failed"
"$WP" plugin install classic-editor --activate || warn "classic-editor install failed"

step "Storing a deeply nested serialized option"
# JSON gets persisted as a serialized PHP array via wp option update --format=json,
# which is exactly the shape we want to exercise the URL replacer.
nested_json=$(cat <<'JSON'
{
  "site_links": {
    "primary": "http://origen.volcan.localhost:8080/",
    "feeds":   ["http://origen.volcan.localhost:8080/feed/", "http://origen.volcan.localhost:8080/comments/feed/"]
  },
  "redirects": [
    { "from": "http://origen.volcan.localhost:8080/old", "to": "http://origen.volcan.localhost:8080/new" },
    { "from": "//origen.volcan.localhost:8080/cdn",       "to": "//origen.volcan.localhost:8080/static" }
  ],
  "rich": {
    "html_blob": "<a href=\"http://origen.volcan.localhost:8080/page-a\">a</a>",
    "encoded":   "http%3A%2F%2Forigen.volcan.localhost%3A8080%2Fencoded"
  }
}
JSON
)
printf '%s' "$nested_json" | "$WP" option update volcan_seed_nested --format=json
ok "Stored option volcan_seed_nested"

printf '\n%sSeed complete.%s Visit http://origen.volcan.localhost:8080/wp-admin to inspect.\n\n' "$GREEN" "$RESET"
