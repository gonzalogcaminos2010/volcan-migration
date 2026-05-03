# Volcán Migration — local development environment

Docker-based dev setup for the **Volcán Migration** WordPress plugin, optimised
for **Windows 11 + WSL2 + Docker Desktop** with **Laravel Herd** running
natively on Windows.

> The whole stack (WordPress origen, WordPress destino, two MariaDBs,
> phpMyAdmin, Mailpit, Traefik) lives behind a single reverse proxy on
> `*.volcan.localhost:8080`, so it never collides with Herd or any other
> tool listening on Windows :80 / :443.

---

## 1. Requirements

| Component | Version | Notes |
| --- | --- | --- |
| Windows | 11 | 10 (21H2+) also works |
| WSL2 distro | Ubuntu 22.04 / 24.04 | Run `wsl --version` to confirm WSL 2 |
| Docker Desktop | 4.30+ | WSL2 backend, **Ubuntu integration enabled** in Settings → Resources → WSL Integration |
| Editor | VS Code with the **WSL** extension (recommended) | |

Verify Docker can talk to WSL:

```bash
docker info >/dev/null && echo "ok" || echo "broken"
```

If that fails, open Docker Desktop → Settings → Resources → WSL Integration and
enable your Ubuntu distro.

---

## 2. Coexistence with Laravel Herd

Herd binds Windows :80 and :443 on `localhost`, and Docker Desktop publishes
ports to that same Windows `localhost`. To avoid the clash:

- Traefik listens on **8080** (web) and **8081** (dashboard).
- Every service in this stack is reached via `http://<name>.volcan.localhost:8080`.
- We never expose 80, 443, 53, 3306, or 3307 to the host. The MariaDB instances
  stay on the internal Compose network, so the existing `fleet-american-advisor`
  MySQL on :3307 is untouched.

If something is already on 8080 or 8081, change `HTTP_PORT` /
`TRAEFIK_DASHBOARD_PORT` in `.env`.

---

## 3. Quick start

```bash
cd ~/proyectos/volcan-migration
./scripts/bootstrap.sh
```

`bootstrap.sh` is idempotent — it runs `doctor.sh` first, generates `.env`
with random DB passwords on first run, builds the dev image, brings the stack
up, waits for healthchecks, and runs `wp core install` on both sites.

Re-running it on an already-installed environment is safe: it detects the
existing install and only re-applies changes.

To wipe everything:

```bash
./scripts/reset.sh           # removes containers + volumes + .env
./scripts/reset.sh --keep-env  # keeps .env (passwords)
```

---

## 4. URLs and credentials

| Service | URL | Notes |
| --- | --- | --- |
| Origen (WordPress) | <http://origen.volcan.localhost:8080> | Site to be migrated |
| Origen admin | <http://origen.volcan.localhost:8080/wp-admin> | |
| Destino (WordPress) | <http://destino.volcan.localhost:8080> | Clean target site |
| Destino admin | <http://destino.volcan.localhost:8080/wp-admin> | |
| phpMyAdmin | <http://pma.volcan.localhost:8080> | Selector at login: `db-origen` / `db-destino` |
| Mailpit (UI) | <http://mail.volcan.localhost:8080> | Captures every `wp_mail()` |
| Traefik dashboard | <http://traefik.volcan.localhost:8081/dashboard/> | Port 8081, not 8080 |

WordPress admin defaults (override in `.env`):

- User: `admin`
- Password: `admin`
- Email: `admin@volcan.localhost`

DB credentials are auto-generated into `.env` on first bootstrap. Read them
with `cat .env` from the repo root. They are also passed to phpMyAdmin
through environment variables — just paste them at the login form.

---

## 5. Why `.localhost` and why port 8080?

- **`.localhost` is reserved by RFC 6761.** Browsers (Chrome, Firefox, Edge,
  Safari) resolve any `*.localhost` name to 127.0.0.1 on their own — no
  `/etc/hosts`, no `dnsmasq`, no Windows hosts file.
- **Herd uses `dnsmasq` against the Windows hosts file** for `*.test`. We
  intentionally avoid `.test` so the two systems can coexist.
- **Port 8080** keeps us off Herd's :80, off IIS, and off Apple's AirPlay
  receiver port (5000). 8081 is similarly free for the Traefik dashboard.

`getent hosts origen.volcan.localhost` may return nothing in WSL — that's
expected. The browser still resolves it correctly.

---

## 6. VS Code with WSL

```bash
cd ~/proyectos/volcan-migration
code .
```

The bottom-left of the VS Code window should read **WSL: Ubuntu**. If it
shows just a path, install the **WSL** extension and re-open the folder via
`Ctrl+Shift+P` → *Reopen Folder in WSL*.

---

## 7. Xdebug in WSL2

The dev image ships Xdebug 3, configured in trigger mode (`xdebug.start_with_request=trigger`).
That means Xdebug only attaches when you append `?XDEBUG_TRIGGER=VOLCAN`,
send the cookie, or use the Xdebug browser extension.

`host.docker.internal` resolves correctly under Docker Desktop with the WSL2
backend (Docker 20.10+). Verify it from inside a container:

```bash
docker compose run --rm wpcli-origen getent hosts host.docker.internal
```

You should see something like `192.168.65.254 host.docker.internal`.

### `.vscode/launch.json` (suggested)

```jsonc
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Listen for Xdebug (Volcán)",
      "type": "php",
      "request": "launch",
      "port": 9003,
      "pathMappings": {
        "/var/www/html/wp-content/plugins/volcan-migration": "${workspaceFolder}",
        "/var/www/html": "${workspaceFolder}/.docker-wp-stub"
      },
      "log": false
    }
  ]
}
```

The first mapping is the only one you need to step through plugin code. The
second is harmless — it just keeps Xdebug quiet when stepping into core.

---

## 8. OAuth Google — redirect URIs

When creating the Google Cloud OAuth Client (Web application), register
both redirect URIs:

```
http://origen.volcan.localhost:8080/wp-admin/admin.php?page=volcanmig-settings&volcanmig_oauth_callback=1
http://destino.volcan.localhost:8080/wp-admin/admin.php?page=volcanmig-settings&volcanmig_oauth_callback=1
```

(The exact callback URL is whatever the plugin's settings page uses; keep both
hostnames so you can connect from either site.)

---

## 9. Useful commands

```bash
# WP-CLI on either site
./scripts/wp-origen.sh  plugin list
./scripts/wp-destino.sh option get siteurl

# Tail logs
./scripts/logs.sh                 # all services
./scripts/logs.sh wp-origen       # just one

# Seed origen with realistic content
./scripts/seed-origen.sh

# Re-run diagnostics anytime
./scripts/doctor.sh
```

---

## 10. Troubleshooting

**Site does not load.** Run `./scripts/doctor.sh`. The most common cause is a
process on the Windows side already listening on :8080 (Herd, IIS, Skype,
node dev server). Either stop it or change `HTTP_PORT` in `.env` and re-run
`bootstrap.sh`.

**The repo is on `/mnt/c/...`.** Move it to the WSL2 native filesystem
(`~/proyectos/volcan-migration`). Bind-mount I/O on `/mnt/c` is 10–50× slower
and Composer/PHPUnit will crawl.

**`docker compose` not found.** Docker Desktop 20.10+ ships `docker compose`
(without the dash). Update Docker Desktop. The legacy `docker-compose` binary
is not used here.

**`host.docker.internal` does not resolve.** Make sure you are using Docker
Desktop with the WSL2 backend (not Docker Engine compiled inside WSL). The
`extra_hosts: host.docker.internal:host-gateway` line in `compose.yml` is the
fallback.

**Mail does not arrive.** It never does — Mailpit catches it. Open
<http://mail.volcan.localhost:8080>.

**Plugin changes do not show up.** The repo root is bind-mounted into both
WordPress containers at `/var/www/html/wp-content/plugins/volcan-migration`.
If you cloned the repo on `/mnt/c`, inotify events are unreliable; move the
repo to WSL2 native storage.

**Traefik dashboard shows nothing.** Visit `http://traefik.volcan.localhost:8081/dashboard/`
(note the trailing slash and the **8081** port).
