# Quickstart — Volcán Migration v1.0

**Feature**: Full-Site Migration vía Google Drive
**Date**: 2026-05-03

This is the end-to-end smoke test the plugin must pass before a release tag is cut. It is the manual-and-automatable script that exercises the spec's primary user stories (US1–US7) on real fixtures. Anyone with two WordPress installs and a Google account can follow it.

---

## 0. Prerequisites

You will need:

- **Two WordPress sites** — call them `site-A` (origin) and `site-B` (destination). Both:
  - WordPress ≥ 6.0, PHP ≥ 7.4 (preferably 8.x), MySQL 5.7+ / MariaDB 10.3+.
  - On shared-hosting-like limits: `memory_limit ≥ 256M`, `max_execution_time ≥ 300`, `upload_max_filesize` deliberately small (e.g. `2M`) to verify chunked PC upload.
  - Different domains (e.g. `https://site-a.local` and `https://site-b.local/blog/`) so the URL-replacement scenario is exercised including a subdirectory change.
- **A Google account** with at least 10 GB free in Drive.
- **A Google Cloud project** with an OAuth 2.0 Client ID configured for "Web application", with the redirect URI:
  - `https://site-a.local/wp-admin/admin.php?page=volcanmig-settings&volcanmig_oauth_callback=1`
  - `https://site-b.local/blog/wp-admin/admin.php?page=volcanmig-settings&volcanmig_oauth_callback=1`
- **Test content on `site-A`**: at least one post with embedded image (uploads), one custom widget that stores a serialized array containing the site URL, one user-meta entry containing the site URL nested in a serialized object.

---

## 1. Install + activate (US1)

On `site-A`:

```text
1. Upload the plugin zip via Plugins → Add New → Upload Plugin.
2. Activate "Volcán Migración".
3. A new admin menu "Volcán Migración" appears.
4. Open the menu → "Settings" tab.
5. Verify: Client ID and Secret fields are empty; status reads "No conectado"; "Conectar Drive" is disabled.
```

**Acceptance**: matches US1 §1 — UI shows empty fields, `No conectado`, button disabled.

---

## 2. Save credentials (US1)

```text
1. Paste your Client ID and Secret from Google Cloud Console.
2. Submit.
3. Verify: status still "No conectado" but "Conectar Drive" now enabled.
4. Reload the page → values still present (encrypted at rest).
```

**Acceptance**: matches US1 §2.

---

## 3. Connect Drive (US2)

```text
1. Click "Conectar Drive".
2. Top-window redirect to Google's consent screen.
3. Approve the requested scope ("View and manage Google Drive files and folders that you have opened or created with this app").
4. Google redirects back to the plugin's settings page.
5. Verify: status now "Conectado a <your email>"; quota shown as "X.YY GB used / Z.ZZ GB total"; "Desconectar" button visible.
6. Verify the plugin created a folder in Drive named like "Volcán Migration / site-a.local".
```

**Acceptance**: matches US2 §1, §2.

---

## 4. Export the site (US3)

```text
1. Open "Export" tab.
2. Defaults: include uploads, themes, plugins, mu-plugins.
3. Click "Empezar export".
4. Watch the progress bar: it should advance through "Volcando base de datos" → "Empaquetando uploads" → "Empaquetando themes" → ... → "Finalizando".
5. Upon completion the UI shows a download link AND a "Subir a Drive" button.
6. Verify the archive was written under wp-content/uploads/volcan-migration/exports/site-...volcan with the expected sha256 (cross-check via the UI's "details" toggle).
```

**Cancellation sub-test**:

```text
7. Start a fresh export.
8. Click "Cancelar" mid-way.
9. Verify the operation row goes to status=cancelled within ~3 s; tmp directory removed; UI shows "Cancelado por el usuario".
```

**Exclusion sub-test**:

```text
10. Start a fresh export with "Incluir uploads" UNCHECKED.
11. Verify the resulting archive's manifest shows `"include":{"uploads":false,...}`.
12. Verify the archive size is markedly smaller than the full one.
```

**Acceptance**: matches US3 §1–§5.

---

## 5. Upload to Drive (US4)

```text
1. From the success screen, click "Subir a Drive".
2. Watch progress bar (8 MiB chunks ≈ 1 % per chunk on a 5 GB site).
3. Mid-way, disconnect your laptop's Wi-Fi for ~20 s, then reconnect.
4. Verify the UI shows "Reanudando..." and resumes from the last successful chunk (no full restart).
5. On completion, verify the file appears in Drive (under "Volcán Migration / site-a.local") with appProperties (visible via Drive's "Details" panel only via API; for the smoke test we accept the UI's success).
```

**Quota sub-test** (only on a Drive whose free space is < archive size):

```text
6. Try uploading. Verify the plugin refuses BEFORE starting the upload, with a message naming the missing bytes.
```

**Acceptance**: matches US4 §1, §2, §5.

---

## 6. List backups (US5)

```text
1. Open "Backups" tab.
2. The just-uploaded archive appears with name, modified date, size.
3. The "site_key_match" badge is green (same site).
4. Click "Descargar" — a binary download starts.
5. Click "Eliminar" on a stale, unused backup → confirm → it disappears from the list AND from Drive.
6. Empty the folder via Drive's web UI; reload "Backups" tab → "No hay backups todavía".
```

**Acceptance**: matches US5 §1–§5.

---

## 7. Import on a different domain (US6)

Switch to `site-B`.

```text
1. Install + activate the plugin (US1 again).
2. Save the same Client ID / Secret (the same Google Cloud project can have multiple redirect URIs).
3. Connect Drive (US2 again, same Google account).
4. Open "Backups" tab on site-B.
5. The site-A backup appears with a yellow "site_key_match: no" badge — the UI warns "este backup pertenece a otro sitio".
6. Click "Importar" on it.
7. The plugin downloads the archive (ticked progress).
8. The plugin parses the manifest and shows: "Origen: https://site-a.local → Destino: https://site-b.local/blog. ¿Continuar?".
9. Click "Sí, importar".
10. Watch the progress through validate → safety_backup → files → db → url_replace → prefix_adjust.
11. On completion, log out and log back into site-B.
12. Verify:
    - Posts from site-A appear.
    - Embedded images load (uploads were copied).
    - Internal links go to https://site-b.local/blog/... (URL replacement worked).
    - The custom widget renders correctly (serialization-safe rewriter worked).
    - The user-meta entry's deserialized URL points to site-B (deep serialization rewriting worked).
```

**Failure-path sub-test**:

```text
13. Start another import; mid-way, kill the PHP process (or take down MySQL for a few seconds).
14. The UI shows "Operación falló — el sitio puede haber quedado a medio importar".
15. Click "Restaurar backup de seguridad".
16. Watch the safety-restore progress.
17. Verify the site is back to its pre-import state.
```

**Acceptance**: matches US6 §1–§6.

---

## 8. Import from PC (US7)

On `site-B`:

```text
1. From "Import" tab, choose "Importar desde mi PC".
2. Select the archive previously downloaded in step 6.4.
3. Watch the chunked upload progress. The plugin's JS auto-detects the server's effective `upload_max_filesize` before opening the upload session by sending a `HEAD` request to `wp-admin/admin-ajax.php` with `Content-Length: 0` and inspecting the negotiated body-size limit; it then picks `min(8 MiB, 0.8 × detected_limit)` as the chunk size for this session. There is **no manual toggle** — the same UI behaves correctly on both unrestricted and tightly-limited hosts. The HEAD-probe + chunk-size negotiation logic is covered by tasks T119–T122.
4. On completion, the import flow auto-starts (US6).
```

**Acceptance**: matches US7 §1, §3.

---

## 9. Logs (US9)

```text
1. Open "Logs" tab.
2. Verify a row per operation (export, upload, import, etc.) with timestamps, status, and result_code.
3. Click into a row → see the per-step log entries.
4. Click "Descargar logs" → save a .txt file.
5. Open the .txt file and grep for "token", "secret", "password" — none should appear (redaction works).
```

**Acceptance**: matches US9 §1–§4.

---

## 10. Multisite (US8)

On a separate multisite install:

```text
1. Network-activate the plugin.
2. As the network admin, configure credentials at the network level.
3. Connect Drive from the network admin → settings.
4. Switch to subsite "/blog2/", run an export.
5. Verify the archive contains only that subsite's tables (`wp_2_*`) and its uploads (`wp-content/uploads/sites/2/...`).
6. Restore that archive into a fresh subsite "/blog9/" with a different prefix → verify prefix adjustment.
```

**Acceptance**: matches US8 §1–§4.

---

## 11. Compliance gate (CI smoke)

These are not manual but must be green to call this script "passing":

```text
1. PHPCS with WordPress ruleset → 0 errors, 0 warnings.
2. PHPStan level 5 → 0 errors.
3. Plugin Check (official action) → 0 warnings.
4. PHPUnit suite → all green; coverage ≥ 70% on Database, Archiver, UrlReplacer, ChunkedUploader; ≥ 90% on UrlReplacer.
5. Network-traffic audit (mitmproxy run during smoke test) → no requests outside *.googleapis.com / *.google.com / api.wordpress.org.
```

---

## 12. Sign-off

If every checkbox above passes on at least one real shared-hosting environment AND on the developer's local docker fixture, the spec's success criteria SC-001 … SC-010 are satisfied for this release.

A failure of **any** sub-test blocks the release until the underlying bug is fixed and the failing sub-test is rerun.
