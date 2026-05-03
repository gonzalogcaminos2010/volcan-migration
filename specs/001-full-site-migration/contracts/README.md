# Volcán Migration — Action Contracts

**Feature**: Full-Site Migration vía Google Drive (`001-full-site-migration`)
**Date**: 2026-05-03

This directory documents every endpoint the plugin exposes. The plugin does **not** publish a public REST API for v1.0; all interactions happen between the bundled JS in `wp-admin` and `admin-ajax.php`. Each contract therefore describes:

- **Action name** (the `action=` parameter sent to `admin-ajax.php`).
- **HTTP method** (always `POST` for mutating actions, `GET` only for read-only listings).
- **Capability** required (`manage_options` single-site / `manage_network_options` multisite — checked by `Admin\Capability::current()`).
- **Nonce action** (every endpoint has its own nonce action, verified with `check_ajax_referer($nonce_action, 'nonce')`).
- **Request payload** (`x-www-form-urlencoded` or `multipart/form-data` for chunked uploads).
- **Successful response** (`200 OK`, `application/json`, with `{ ok: true, ... }`).
- **Error response** (`200 OK` + `{ ok: false, code: '<i18n_key>', message: '<en>'}` — we keep `200` and signal errors in the body so WP's AJAX error handlers don't kick in for handled errors. Unhandled exceptions return `500`.)

Every endpoint extends `Ajax\AjaxHandler` which performs, in order:

1. `Capability::require()` (kills with `wp_send_json_error('forbidden', 403)` if missing).
2. `check_ajax_referer($nonce_action, 'nonce')`.
3. Per-action input validation (sanitization).
4. Dispatch.

## Files

| File              | Covers user stories                            |
|-------------------|------------------------------------------------|
| settings.md       | US1 (configure plugin)                         |
| oauth.md          | US2 (connect/disconnect Drive)                 |
| export.md         | US3 (export site)                              |
| upload.md         | US4 (upload backup to Drive)                   |
| backups.md        | US5 (list / download / delete in Drive)        |
| import.md         | US6 (import from Drive)                        |
| pc-upload.md      | US7 (import from PC, chunked browser upload)   |
| logs.md           | US9 (logs UI)                                  |

## Common error codes

| Code                  | HTTP | Meaning                                                    |
|-----------------------|------|------------------------------------------------------------|
| `forbidden`           | 403  | Capability check failed                                    |
| `bad_nonce`           | 403  | Nonce missing or expired                                   |
| `invalid_input`       | 400  | A required field was missing or failed sanitization        |
| `not_connected`       | 409  | Drive isn't connected; reconnect required                  |
| `lock_busy`           | 409  | Another operation is running for this site                 |
| `not_found`           | 404  | Operation, backup, or upload session not found             |
| `quota_exceeded`      | 507  | Drive storage too small for the upload                     |
| `network_error`       | 502  | Transient Drive / network failure (caller may retry)       |
| `version_mismatch`    | 409  | Backup's WP major version incompatible with destination    |
| `internal_error`      | 500  | Unexpected; logged with redaction                          |
