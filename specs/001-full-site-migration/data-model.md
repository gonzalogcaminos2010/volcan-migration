# Phase 1 Data Model — Volcán Migration v1.0

**Feature**: Full-Site Migration vía Google Drive
**Date**: 2026-05-03
**Source spec**: `spec.md` §"Key Entities"
**Storage decisions**: see `research.md` R4 (token cipher), R8 (multisite), R10 (operations + logs schema).

This document is the canonical mapping between the conceptual entities from the spec and their concrete persistence in WordPress (options, network options, custom tables, filesystem paths).

---

## 1. Entity overview

| Entity              | Storage                                                                   | Cardinality                                     | Lifetime                          |
|---------------------|---------------------------------------------------------------------------|-------------------------------------------------|-----------------------------------|
| Site                | Derived (no row of its own)                                               | 1 per single-site, N per multisite              | Same as the WordPress install     |
| Drive Connection    | `wp_options` (single) / `wp_sitemeta` (network) — encrypted blob          | 1 per site / 1 per network                      | Until user disconnects            |
| Settings            | `wp_options` / `wp_sitemeta`                                              | 1                                               | Until plugin uninstall             |
| Operation           | `wp_volcanmig_operations` (network-wide on multisite, with `blog_id`)     | N per Site                                      | 90 days OR last 50 per blog       |
| Log Entry           | `wp_volcanmig_logs`                                                       | N per Operation                                 | Tied to parent Operation          |
| Backup (Drive file) | Lives in user's Drive, indexed in-memory at list time                     | N per Site, in user's Drive folder              | Until user deletes from the plugin or Drive |
| Temp Archive Part   | `wp-content/uploads/volcan-migration/tmp/<op_id>/`                        | 1 per active Operation                          | Removed on completion or cancel   |
| PC Upload Session   | `wp_options['volcanmig_pc_upload_<sid>']` + temp files                    | At most 1 active per site                       | 2 h idle GC                       |

---

## 2. Site

A "Site" in the Volcán Migration sense is the WordPress install (or, on multisite, a single subsite). The plugin does **not** create a row for a Site; instead a Site is identified by:

- `site_key`: a stable string derived as `md5( site_url() . '|' . get_current_blog_id() )`. Used as part of the Drive folder name and as the partition key in custom tables (`blog_id` column suffices for multisite; `site_key` is a defense-in-depth fingerprint stored on the Drive folder's metadata).

Fields exposed at runtime (computed, not stored):

| Field            | Type    | Source                                  | Notes                                       |
|------------------|---------|-----------------------------------------|---------------------------------------------|
| blog_id          | int     | `get_current_blog_id()`                 | 1 on single-site                            |
| site_url         | string  | `site_url()` / `get_blog_option(.., 'siteurl')` | Used for URL replacement origin |
| home_url         | string  | `home_url()`                            |                                             |
| db_prefix        | string  | `$wpdb->prefix`                         | Captured into manifest at export time       |
| wp_version       | string  | `get_bloginfo('version')`               | Captured into manifest                      |
| is_multisite     | bool    | `is_multisite()`                        |                                             |
| capability       | string  | derived                                 | `manage_options` or `manage_network_options` |

**Validation**: nothing to validate; the Site IS the WordPress install. The plugin trusts core's identity helpers.

---

## 3. Drive Connection

Represents the OAuth link to the user's Google account. Exactly one per site (single) / per network (multisite — see research R8).

**Storage key**: `volcanmig_oauth_tokens` (in `wp_options` or `wp_sitemeta`).
**Storage value**: a single base64 string produced by `OAuth\Cipher::encrypt(json_encode($payload))`.

Decrypted payload schema:

| Field             | Type    | Required | Notes                                                                 |
|-------------------|---------|----------|-----------------------------------------------------------------------|
| client_id         | string  | yes      | Google Cloud OAuth Client ID (the user's, never the author's)         |
| client_secret     | string  | yes      | Same                                                                  |
| access_token      | string  | yes      | Short-lived; refreshed transparently                                  |
| refresh_token     | string  | yes      | Long-lived                                                            |
| token_type        | string  | yes      | Almost always `Bearer`                                                |
| expires_at        | int     | yes      | Unix timestamp of access-token expiry                                 |
| scope             | string  | yes      | Must be `https://www.googleapis.com/auth/drive.file`                  |
| account_email     | string  | yes      | The connected account, displayed in the UI                            |
| account_id        | string  | yes      | Google's stable user ID (used for diagnostics, never sent anywhere)   |
| created_at        | int     | yes      |                                                                       |
| updated_at        | int     | yes      |                                                                       |
| key_version       | int     | yes      | Cipher key version (R4)                                               |

**State transitions**:
```
[absent] --save creds--> [credentials_only]
   |                          |
   |                          +-- start oauth --> [pending_consent]
   |                                                   |
   |                                                   +-- callback ok --> [connected]
   |                                                   +-- callback err -> [credentials_only]
   |
   +-- (n/a)
[connected] --tick token expired & refresh ok--> [connected]
[connected] --refresh fails / token revoked --> [credentials_only]  + UI: "reconnect"
[connected] --user disconnects-->  revoke + delete  -> [credentials_only]
[credentials_only] --user clears creds--> [absent]
```

**Validation**:
- `client_id` matches `^[A-Za-z0-9._-]+\.apps\.googleusercontent\.com$` (loose, just to catch typos).
- `client_secret` non-empty, ≤ 256 chars.
- `scope` MUST be exactly the allowed scope; importing any other scope is rejected.

**Security**:
- Decrypted payload never leaves request memory; never logged.
- `Logger::redact()` strips token-like fields by name AND any base64 string ≥ 32 chars adjacent to keys named `token`, `secret`, `password`.

---

## 4. Settings

Plugin-wide preferences. Stored under `volcanmig_settings` (option / network option).

| Field                          | Type    | Default                            | Notes                                                  |
|--------------------------------|---------|------------------------------------|--------------------------------------------------------|
| log_retention_days             | int     | 90                                 | See FR-063                                             |
| log_retention_max_ops_per_blog | int     | 50                                 | See FR-063                                             |
| archive_chunk_bytes            | int     | 4 194 304  (4 MiB)                 | Filterable via `volcanmig_archive_chunk_bytes`         |
| drive_upload_chunk_bytes       | int     | 8 388 608  (8 MiB)                 | Filterable                                             |
| pc_upload_max_bytes            | int     | 10 737 418 240 (10 GiB)            | Filterable                                             |
| default_excluded_paths         | array   | `[]`                               | Per-export overrides via UI                            |
| ui_locale_override             | string  | `''`                               | Empty means follow WP locale                           |

**Validation**: bounds-check all integers; reject negatives. `default_excluded_paths` MUST contain only members of the canonical set `['uploads','themes','plugins','mu-plugins']`.

---

## 5. Operation

A single export / upload / import run. Persisted in `wp_volcanmig_operations` (network-wide on multisite).

> **Why these three and not five?** Downloads from Drive are short-lived streaming operations handled by `BackupDownload` without persistence (the user's browser is the natural progress UI). PC upload sessions live in transients (`wp_options['volcanmig_pc_upload_<sid>']`) because they need resumability without long-term tracking. Neither warrants an `operations` row.

**Schema** (canonical — repeated from research R10 for completeness):
```sql
CREATE TABLE {$wpdb->base_prefix}volcanmig_operations (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  blog_id       BIGINT UNSIGNED NOT NULL DEFAULT 0,
  type          VARCHAR(20)     NOT NULL,
  status        VARCHAR(20)     NOT NULL,
  started_at    DATETIME        NOT NULL,
  finished_at   DATETIME        NULL,
  progress_pct  TINYINT UNSIGNED NOT NULL DEFAULT 0,
  bytes_total   BIGINT UNSIGNED NOT NULL DEFAULT 0,
  bytes_done    BIGINT UNSIGNED NOT NULL DEFAULT 0,
  state_json    LONGTEXT        NOT NULL,
  result_code   VARCHAR(40)     NULL,
  KEY idx_blog_status (blog_id, status),
  KEY idx_started (started_at)
);
```

### 5.1 Field semantics

| Field        | Notes                                                                                       |
|--------------|---------------------------------------------------------------------------------------------|
| type         | Enum: `export`, `upload`, `import`                                                          |
| status       | Enum: `pending`, `running`, `completed`, `cancelled`, `failed`                              |
| state_json   | Step-machine state. Schema depends on `type` (see §5.3). Never contains secrets.            |
| result_code  | Stable code for UI/i18n (e.g. `ok`, `quota_exceeded`, `network_error`, `version_mismatch`). |

### 5.2 Status transitions

```
pending --start--> running
running --finish--> completed
running --user cancel--> cancelled
running --error--> failed
running --tick crash + heartbeat stale--> failed   (lock auto-released; user prompted)
completed | cancelled | failed --(terminal)
```

The state machine is enforced in `OperationRepository::transition($id, $next)` which rejects illegal transitions with an exception.

### 5.3 `state_json` schemas

**Export**:
```jsonc
{
  "step": "db" | "files" | "package" | "done",
  "db": { "tables": ["wp_options", ...], "current_index": 4, "row_offset": 12000 },
  "files": { "set": "uploads"|"themes"|"plugins"|"mu-plugins", "current_path": "...", "byte_offset": 1048576 },
  "manifest": { "wp_version": "6.5.2", "db_prefix": "wp_", "site_url": "https://example.com" },
  "tmp_archive_path": "wp-content/uploads/volcan-migration/tmp/<op_id>/site.volcan",
  "include": { "uploads": true, "themes": true, "plugins": true, "mu-plugins": true }
}
```

**Upload (Drive)**:
```jsonc
{
  "archive_path": "...",
  "drive_session_url": "<encrypted-with-Cipher>",
  "drive_file_id": "1AbC...",
  "byte_offset": 167772160
}
```

**Download (from Drive)**:
```jsonc
{
  "drive_file_id": "1AbC...",
  "local_path": "...",
  "byte_offset": 0
}
```

**Import**:
```jsonc
{
  "archive_path": "...",
  "step": "validate" | "safety_backup" | "files" | "db" | "url_replace" | "prefix_adjust" | "done",
  "safety_backup_path": "...",
  "manifest": { "...": "..." },
  "url_map": { "https://old.com": "https://new.com" },
  "prefix_map": { "wp_": "wp_2_" },
  "current_table": "wp_postmeta",
  "row_offset": 0,
  "files_offset": 0
}
```

**PC Upload**:
```jsonc
{
  "session_id": "...",
  "expected_size": 5368709120,
  "received_bytes": 167772160,
  "next_chunk_index": 20,
  "expected_sha256": "..."
}
```

### 5.4 Validation
- Exactly one Operation per `(blog_id, status='running')` — enforced via the `OperationLock` (R9) and a defensive `SELECT ... FOR UPDATE` (best-effort) at start.
- `bytes_done <= bytes_total` (where `bytes_total` is known).
- `progress_pct = floor(100 * bytes_done / bytes_total)` when `bytes_total > 0`.

### 5.5 Cleanup
- `temp` files for `completed`, `cancelled`, `failed` operations are removed by the closing tick (or by the lock-reaper if the tick crashed).
- The `Rotator` (run daily via WP-Cron) removes operation rows older than 90 days OR exceeding 50 per blog.

---

## 6. Log Entry

Append-only structured logs tied to an Operation.

**Schema**:
```sql
CREATE TABLE {$wpdb->base_prefix}volcanmig_logs (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  operation_id  BIGINT UNSIGNED NOT NULL,
  ts            DATETIME        NOT NULL,
  level         VARCHAR(10)     NOT NULL,
  message       TEXT            NOT NULL,
  context_json  TEXT            NULL,
  KEY idx_operation (operation_id),
  KEY idx_ts (ts)
);
```

| Field        | Notes                                                                          |
|--------------|--------------------------------------------------------------------------------|
| level        | Enum: `debug`, `info`, `warn`, `error`. `debug` only kept when `WP_DEBUG=true`.|
| message      | i18n-friendly: keep the message stable in English; UI translates by code.      |
| context_json | Bounded ≤ 4 KiB; redacted by `Log\Redactor`.                                   |

**Validation**:
- `Redactor::redact()` MUST remove any value whose key matches `/(token|secret|password|access[_-]?key|client[_-]?secret)/i`, plus any base64 blob ≥ 32 chars.
- Test fixture verifies redaction for representative real Drive responses.

**Retention**: Cascading delete when an Operation is rotated.

---

## 7. Backup (Drive file)

The "Backup" entity is **not** stored locally — it lives in the user's Drive folder. The plugin lists it on demand and never caches it.

**Listing query** (Drive API):
```
files.list(
  q = "'<folder_id>' in parents and mimeType='application/octet-stream' and trashed=false",
  fields = "files(id,name,size,modifiedTime,appProperties)",
  orderBy = "modifiedTime desc",
  pageSize = 100
)
```

**Drive `appProperties` we set on every upload**:

| Key                    | Value                                                       |
|------------------------|-------------------------------------------------------------|
| `volcanmig_version`    | The plugin version that produced the archive                |
| `volcanmig_site_key`   | `md5(site_url|blog_id)`                                     |
| `volcanmig_wp_version` | The site's WP version at export time                        |
| `volcanmig_db_prefix`  | The `$wpdb->prefix` used at export time                     |
| `volcanmig_size_bytes` | Stringified size in bytes                                   |
| `volcanmig_sha256`     | Hex SHA-256 of the archive (computed during streaming write)|

These let us validate ownership and sanity at download time without parsing the archive.

**Validation rules at "Import from Drive"**:
- `volcanmig_sha256` must match the recomputed hash after download.
- `volcanmig_wp_version` is compared against destination's `get_bloginfo('version')` per R11.

---

## 8. Temp Archive Part / PC Upload Session

**Temp archive parts** during export:
- Path: `wp-content/uploads/volcan-migration/tmp/<op_id>/site.volcan` (and possibly `.partial`).
- Lifetime: removed at the closing tick of the operation (success or failure).
- Permissions: created with WordPress's `wp_mkdir_p()` (default umask). The parent directory has a `.htaccess` denying direct access AND an `index.html` empty stub for Nginx.
- A `wp_volcanmig_tmp_gc` daily WP-Cron event removes any subdirectory older than 24 h whose `<op_id>` is not in `running` state.

**PC upload sessions**:
- Stored as `wp_options['volcanmig_pc_upload_<sid>']` with `{ created_at, last_seen_at, expected_size, expected_sha256, received_chunks, total_chunks }`.
- Idle TTL: 2 h.
- Lock: shares the per-site `OperationLock`.

---

## 9. Relationships

```text
Site (1)
 ├── Drive Connection (0..1)
 ├── Settings (1)
 ├── PC Upload Session (0..1)               # site-level transient, not an Operation
 └── Operation (0..N)                       # type ∈ {export, upload, import}
        ├── Log Entry (0..N)
        └── Temp Archive Part (0..1)        # only while running
```

The Drive Backup files are external to the relational model; the bridge is the per-site Drive folder ID stored in the Drive Connection payload (`drive_folder_id`).

---

## 10. Migration / installation

On `register_activation_hook`:
1. Create both custom tables via `dbDelta`.
2. Set default `volcanmig_settings` if not present.
3. Schedule the daily `volcanmig_logs_gc`, `volcanmig_tmp_gc`, and `volcanmig_pc_upload_gc` events.
4. NEVER touch token storage on activation. Reactivation preserves an existing Drive Connection.

On `register_uninstall_hook` (in `uninstall.php`):
1. Drop both custom tables.
2. Delete `volcanmig_oauth_tokens`, `volcanmig_settings`, all `volcanmig_pc_upload_*` and `volcanmig_lock_*` options.
3. Recursively remove `wp-content/uploads/volcan-migration/`.
4. Unschedule cron events.

Deactivation deliberately leaves data intact (matches user expectations for "deactivate ≠ uninstall").
