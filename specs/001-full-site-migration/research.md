# Phase 0 Research — Volcán Migration v1.0

**Feature**: Full-Site Migration vía Google Drive
**Date**: 2026-05-03
**Status**: Complete — all NEEDS CLARIFICATION items resolved.

This document records every key technical decision the plan depends on, the rationale, and the alternatives that were considered and rejected. Each section starts with "Decision / Rationale / Alternatives" so the design constraints are auditable from a single place.

---

## R1. Long-running operations on shared hosting (5 GB / 256 MB / 300 s)

**Decision**: Re-entrant background loopback via `admin-ajax.php`. The browser polls a `volcanmig_*_tick` action every ~2 s. Each tick processes one chunk (a fixed slice of bytes for files; a fixed number of rows for DB) and returns when **either** 25 s elapses **or** memory crosses ~70 % of `ini_get('memory_limit')`. State (current step, byte offset, row offset, chunk index, checkpoint hash) is persisted on every tick to `wp_volcanmig_operations` so a crashed tick is resumable.

**Rationale**:
- WP core's own scheduler (`wp_cron`) is unreliable on low-traffic sites and only fires when a request comes in. Loopback driven by the open admin tab guarantees forward progress while the user is watching.
- The "WP Background Process" pattern (popularized by deliciousbrains/wp-background-processing) is battle-tested; we reimplement it minimally to avoid a Composer runtime dep.
- Splitting work into small ticks (≤ 25 s) leaves headroom under the typical 300 s `max_execution_time` and 256 MB memory ceilings.
- Persisting checkpoints makes cancellation safe: cancellation is honored at the next tick boundary.

**Alternatives considered**:
- **Pure CLI / WP-CLI commands** — rejected: §IV.7 explicitly says the plugin must run from the dashboard without shell access.
- **`wp_cron` only** — rejected: unreliable on cold sites, hard to surface live progress to the UI.
- **Action Scheduler (woocommerce/action-scheduler)** — viable but adds a ~30 KLOC dependency, an extra DB table set, and another moving part. Cost outweighs benefit for our single-orchestrator use case (§III.5).

**Concrete settings**:
- Tick budget: `min(25 s, 0.85 × max_execution_time)` with a 5 s safety margin.
- Memory budget: abort current chunk when `memory_get_usage(true) > 0.70 × memory_limit`.
- Chunk sizes: archive write chunks 4 MiB; DB dump rows 1 000 per tick (auto-scaling down on long rows); Drive upload chunks 8 MiB.
- Polling: 2 s default, exponential backoff to 10 s if tick durations exceed budget.

---

## R2. Custom archive format vs ZIP / tar

**Decision**: Custom streaming binary format `.volcan` (a "packed" file): magic header + manifest JSON + length-prefixed entries (`[entry_header_v1][payload_bytes]…`). No central directory. Read sequentially, write sequentially. No compression in v1.x (ship `STORE` only); each entry stores `crc32` + `sha256` for integrity.

**Rationale**:
- ZIP requires a central directory at the **end** of the file, which forces the writer to either know all entry offsets in advance or seek backward — both fight chunked streaming on shared hosting.
- ZIP64 and PHP's `ZipArchive` have spotty large-file behavior and PHP allocates per-entry overhead.
- TAR is streaming-friendly but has 512-byte block padding and stale POSIX edge-cases; a minimal custom format is smaller and easier to validate.
- Storing without compression matches what users actually need: most of the bytes are already-compressed images/JPEGs/PNGs/MP4s. We trade ~15 % file-size overhead for guaranteed memory ceiling and reliable streaming.

**Alternatives considered**:
- **`ZipArchive` (PHP)** — rejected: requires final seek, edge-cases on >2 GB without ZIP64, hostile on low memory.
- **`PharData` / tar** — rejected: header padding, less control over chunked writes, adds Phar baggage.
- **Per-file split archives** — rejected: complicates a single-file Drive upload and adds reconstruction complexity at restore.
- **Compress with gzip** — rejected for v1.0: the extra CPU cost is real on shared PHP, and compression of already-compressed media is near zero. Re-evaluable in v1.x if measurements show otherwise.

**Format sketch**:
```
[8 bytes  magic         "VOLCAN1\n"]
[4 bytes  manifest_len  big-endian uint32]
[N bytes  manifest_json UTF-8 JSON: site URL, prefix, included sets, entry count, total bytes]
repeat:
  [1 byte  entry_type   1=dbsegment 2=file 3=meta]
  [2 bytes path_len     big-endian uint16]
  [path_len  path       relative path, never absolute, never with ".."]
  [8 bytes  size        big-endian uint64]
  [4 bytes  crc32       big-endian]
  [32 bytes sha256      raw bytes]
  [size bytes payload]
[1 byte  trailer_type=0xFF terminator]
```

`PathGuard` (per §V.5) refuses any path that is not relative and inside the destination root after canonicalization.

---

## R3. Resumable upload to Google Drive

**Decision**: Use Drive's **resumable upload session** (`uploadType=resumable`). The plugin requests a session URL once per upload, stores it on the Operation row, and uploads 8 MiB chunks via `PUT` with `Content-Range` headers, supporting 308 "Resume Incomplete" and re-querying the session on any 5xx.

**Rationale**:
- Drive's resumable session is the only way to recover from a transient disconnect without resending the whole file. It supports up to 5 TB per upload session.
- 8 MiB chunks balance Drive's recommendation (≥ 256 KiB, ≤ 5 GiB) with our memory cap. At 8 MiB a single chunk fits comfortably in PHP memory and corresponds to ~1–2 s of typical hosting bandwidth.
- The Google API client's `MediaFileUpload` helper handles 308/Range bookkeeping when `resumable=true` is set; we wrap it in our own `ResumableUploader` so we can retry with backoff and persist the session URL between ticks.

**Alternatives considered**:
- **Multipart upload** (single request) — rejected: not resumable; fails the >2 GB / network-blip requirement (US4 / FR-021).
- **Simple media upload** — same problem; one request, one shot.
- **Direct chunked upload bypassing the SDK** — viable but duplicates a lot of OAuth + retry logic the SDK already gives us. Cost > benefit.

**Retry policy**:
- 408, 429, 5xx: exponential backoff 1, 2, 4, 8, 16 s, then surface to UI as "retry".
- 401 (token expired mid-upload): refresh token, retry the failed chunk.
- 403 quotaExceeded: surface immediately to UI; never auto-retry.
- Cancellation: send `DELETE` to the resumable session URL, then drop temp file.

---

## R4. OAuth token storage (encryption at rest)

**Decision**: AES-256-GCM with a key derived via HKDF-SHA256 from the concatenation of WordPress's `AUTH_KEY` and `SECURE_AUTH_KEY` constants, with a per-install `salt` stored in `wp_options`. Ciphertext + IV (12 bytes) + auth tag (16 bytes) + key version are stored together as a single base64 blob in `wp_options['volcanmig_oauth_tokens']` (or `wp_sitemeta` on multisite).

**Rationale**:
- Pure DB dumps without filesystem access cannot decrypt — defeats the threat of stolen DB backups (FR-004).
- HKDF avoids using `AUTH_KEY` directly as a 256-bit key (which it isn't, in length or distribution).
- Storing the key version lets us rotate the algorithm later without breaking existing installs.
- GCM gives us authentication "for free", so a tampered ciphertext fails verification.

**Alternatives considered**:
- **`openssl_encrypt` with AES-CBC + HMAC** — works but is more code and easier to misuse than GCM.
- **`sodium_*` primitives (libsodium)** — bundled in PHP 7.2+, more modern, but PHP 7.4 hosts may have it disabled. We prefer `openssl_*` because openssl is universally available; we still feature-detect sodium and prefer it when available.
- **Storing tokens in plaintext** — rejected: violates §V.6 / FR-004.
- **Storing tokens in a file outside web root** — viable, but on shared hosting we can't reliably guarantee a writable location outside `wp-content/`. DB-with-encryption is more portable.

**Key rotation**: when `AUTH_KEY` changes (admin rotated salts), decryption fails → tokens are invalidated → user is prompted to reconnect (matches the edge-case in spec).

---

## R5. PHP-Scoper packaging strategy

**Decision**: Build-time PHP-Scoper run that rewrites `google/apiclient` (and its transitive deps `google/auth`, `firebase/php-jwt`, `guzzlehttp/guzzle`, `psr/*`) under `VolcanMigration\Vendor\` and commits the scoped output under `volcan-migration/src/Vendor/`. CI verifies that no top-level `Google\`, `GuzzleHttp\`, `Psr\` symbols leak into the shipped zip.

**Rationale**:
- §III.4 / §IV.3 forbid Composer at runtime. Vendoring scoped code is the only path that satisfies both "use a third-party SDK" and "no Composer when the user installs the plugin".
- Scoping (vs raw vendoring) prevents collisions with other plugins shipping their own copies of Guzzle / google-api-client.
- Committing the scoped output (instead of running PHP-Scoper as part of `composer install`) keeps the user-installable zip self-contained.

**Alternatives considered**:
- **Raw vendoring without scoping** — rejected: fatal-error-prone collisions when other plugins ship the same lib.
- **Hand-rolled HTTP client for Drive** — viable (Drive's REST is fairly thin) but adds significant maintenance burden, especially for OAuth refresh and resumable session bookkeeping. We accept the ~3 MB of vendor code in exchange for using a maintained client.
- **`mozart` (alternative to PHP-Scoper)** — comparable, but PHP-Scoper is the WP.org-blessed standard and has better community support.

**Build flow** (in `tools/build-release.sh`):
1. `composer install --no-dev` into a build dir.
2. `php-scoper add-prefix` with `tools/scoper.inc.php` → `volcan-migration/src/Vendor/`.
3. Rewrite the autoloader to use our PSR-4 autoloader instead of Composer's.
4. Strip dev files (tests/, .github/, docs/) from the vendored output.
5. Run a sanity grep for unscoped `\Google\` / `\GuzzleHttp\` references.

---

## R6. Serialization-safe URL replacement

**Decision**: Replace URLs by **rewriting serialized PHP byte streams** without ever calling `unserialize()` on untrusted DB content. The replacer walks the value as a token stream (`s:<len>:"<bytes>"`, `a:<count>:{…}`, `O:<class_len>:"<class>":<count>:{…}`, etc.); when a `s:` token's bytes contain the search string, it substitutes them, **recomputes the byte length**, and rewrites the `s:<len>` prefix.

**Rationale**:
- `unserialize()` on attacker-controlled data is a known RCE risk (PHP object injection); a dump from another site IS attacker-controlled data from the destination's point of view.
- Length-aware token rewriting is the technique used by mature tools (e.g. WordPress's own Search-Replace-DB, `wp search-replace`) and preserves nested arrays/objects exactly.
- Doing this in a single pass per row keeps memory bounded.

**Rationale for rejecting common shortcuts**:
- **`unserialize` → modify → `serialize`** — rejected: object injection, plus loses information for objects whose classes don't exist in the destination.
- **Naïve `str_replace` on the raw DB bytes** — rejected: corrupts serialized strings (`s:23:"https://old.com/about"` becomes `s:23:"https://new.com/about"` which now has wrong length).
- **Regex-based length fix** — fragile; fails on nested or multibyte content.

**Validation**:
- Test fixtures (`tests/fixtures/serialized/`) cover: deeply nested arrays, `stdClass`, custom-class object serialization, arrays of URLs, URL-encoded URLs in JSON-encoded blobs (these we can't safely rewrite — the rewriter only touches PHP-serialized scopes, not nested JSON; behavior documented in `quickstart.md`).
- Coverage gate ≥ 90 % on `UrlReplacer` (above the §VI baseline of 70 %, given the security sensitivity).

---

## R7. Browser → server chunked upload (US7 / FR-046)

**Decision**: A custom JS uploader (`admin-pc-upload.js`) slices the file with `Blob.slice()` into 8 MiB chunks, POSTs each via `fetch()` to `volcanmig_pc_upload_chunk` (a per-chunk action with nonce + chunk index + total chunks + upload session id). The server appends each chunk to `uploads/volcan-migration/tmp/<session_id>/file.part`. A final `volcanmig_pc_upload_finalize` call validates total size + sha256 and renames to `file.volcan`, then triggers the import flow.

**Rationale**:
- `upload_max_filesize` / `post_max_size` are per-request limits. Chunking sidesteps both.
- `fetch()` exposes upload progress via the body in modern browsers; we additionally surface server-side progress via the operations table for cross-tab consistency.
- An 8 MiB chunk size matches the Drive upload chunk size, simplifying configuration and minimizing the maximum request body that the server must accept.

**Alternatives considered**:
- **`tus` protocol with a PHP server lib** — solid spec but adds a non-trivial dependency and requires Composer or vendoring another lib (§III.5). Deferred.
- **Increasing `upload_max_filesize` via .htaccess** — rejected: doesn't work on Nginx, often blocked by the host, and violates "no shell access" principle.

**Concurrency / abuse limits**:
- One PC upload session per site at a time (uses the same `OperationLock` as exports/imports).
- Sessions older than 2 h with no chunks are GC'd by `volcanmig_pc_upload_gc` cron event.
- Server enforces total bytes ≤ a configurable maximum (default 10 GB, settable via `volcanmig_pc_upload_max_bytes` filter).

---

## R8. Multisite operation model

**Decision**: Per-subsite operations run with **`manage_network_options`** capability checks (per spec FR-051) and write/read tables `wp_volcanmig_operations` / `wp_volcanmig_logs` at the **network level** with a `blog_id` column. Drive credentials and tokens live at the **network level** (`wp_sitemeta`) — there is one Drive connection per network, and per-subsite folders are children of a single network root folder. Each subsite gets its own folder named by the subsite's domain/path.

**Rationale**:
- Constitution §III.3 mandates multisite from day one. Storing tokens at network level matches WP's typical "network-wide service config + per-site state" pattern (cf. Akismet, Jetpack).
- Per-subsite Drive folders make backups discoverable and let an operator restore a single subsite without touching siblings.
- Custom tables at network level avoid the trap of network-active plugins that double-write to per-blog tables.

**Alternatives considered**:
- **Per-subsite OAuth credentials** — rejected: requires every subsite admin to configure Google Cloud, which is a usability disaster on a typical multisite.
- **Single shared Drive folder for the whole network** — rejected: collapses backups from different subsites into one bucket; harder to disambiguate.

**Capability matrix**:
| Context        | Action menu visible to        | Capability checked       |
|----------------|-------------------------------|--------------------------|
| Single-site    | Site admins                   | `manage_options`         |
| Multisite root | Network admins (no per-blog)  | `manage_network_options` |
| Multisite blog | Network admins, in blog scope | `manage_network_options` |

---

## R9. Single-operation lock per site

**Decision**: Use a **transient with a short TTL + monotonic heartbeat**. `OperationLock::acquire($blog_id, $op_id)` does a single `add_option`/`add_site_option` (which is atomic at the DB layer because of the `UNIQUE` constraint on the option name) of `volcanmig_lock_<blog_id>` storing `{op_id, started_at}`. While the operation runs, each tick updates `last_seen_at`. If a lock is older than `tick_budget × 4` without heartbeat, it is considered abandoned and may be force-released.

**Rationale**:
- WP options have a UNIQUE constraint on `option_name`, so `add_option` is the closest WP gives to a CAS primitive.
- Transients alone aren't reliable for locks (object cache may drop them); options-with-heartbeat are durable.

**Alternatives considered**:
- **MySQL `GET_LOCK`** — works on MySQL but breaks on many shared hosts that disable it; not portable.
- **`flock()` on a file** — fragile across PHP-FPM workers and not always available on shared hosting.

---

## R10. Logs schema and rotation

**Decision**: Two custom tables, network-wide on multisite:
```sql
CREATE TABLE wp_volcanmig_operations (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  blog_id       BIGINT UNSIGNED NOT NULL DEFAULT 0,
  type          VARCHAR(20)     NOT NULL,        -- export|upload|download|import|pc_upload
  status        VARCHAR(20)     NOT NULL,        -- pending|running|completed|cancelled|failed
  started_at    DATETIME        NOT NULL,
  finished_at   DATETIME        NULL,
  progress_pct  TINYINT UNSIGNED NOT NULL DEFAULT 0,
  bytes_total   BIGINT UNSIGNED NOT NULL DEFAULT 0,
  bytes_done    BIGINT UNSIGNED NOT NULL DEFAULT 0,
  state_json    LONGTEXT        NOT NULL,        -- step, offsets, drive_session_url (encrypted), file_path
  result_code   VARCHAR(40)     NULL,
  KEY idx_blog_status (blog_id, status),
  KEY idx_started (started_at)
);

CREATE TABLE wp_volcanmig_logs (
  id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  operation_id  BIGINT UNSIGNED NOT NULL,
  ts            DATETIME        NOT NULL,
  level         VARCHAR(10)     NOT NULL,        -- debug|info|warn|error
  message       TEXT            NOT NULL,
  context_json  TEXT            NULL,
  KEY idx_operation (operation_id),
  KEY idx_ts (ts)
);
```
**Rotation**: A daily WP-Cron event `volcanmig_logs_gc`:
- Deletes operations older than 90 days OR keeps only the most recent 50 per blog, whichever truncates more.
- Deletes orphan log rows (`operation_id` no longer in `operations`).

**Rationale**: Custom tables let us index by status/blog efficiently and avoid bloating `wp_options`. A `state_json` LONGTEXT keeps state-machine flexibility without schema churn.

**Alternatives considered**:
- **Storing operations in `wp_options`** — rejected: queries by status/blog become full table scans; cleanup is manual.
- **Custom post types** — overkill and pollutes `wp_posts` with technical metadata.

---

## R11. Major-version cross-WP guard

**Decision**: At import start, compare `manifest.json.wp_version` (recorded at export time) and `get_bloginfo('version')`. If the **major.minor** versions differ in a way that crosses a major core release boundary that WordPress itself flags as a breaking upgrade, refuse and surface a clear error per spec §"Edge Cases" and constitution §X.5.

**Rationale**:
- Constitution explicitly puts cross-major migration **out of scope**.
- Refusing early (before the safety backup) saves the user from a half-broken site.

**Alternatives considered**:
- **Trying to migrate anyway** — rejected: scope creep + safety risk.
- **Refusing on **any** version difference** — rejected: too strict; minor differences are common and safe.

---

## R12. Public hook surface

**Decision**: Expose a small, stable set of `volcanmig_*` filters/actions for power users while keeping the internal API private:
- `volcanmig_export_excluded_paths` (filter, array)
- `volcanmig_archive_chunk_bytes` (filter, int — default 4 MiB)
- `volcanmig_drive_upload_chunk_bytes` (filter, int — default 8 MiB)
- `volcanmig_drive_oauth_scopes` (filter, array — default `['https://www.googleapis.com/auth/drive.file']`)
- `volcanmig_pc_upload_max_bytes` (filter, int — default 10 GB)
- `volcanmig_log_redaction_patterns` (filter, array of regex)
- `volcanmig_before_import` / `volcanmig_after_import` (actions, $operation_id)
- `volcanmig_before_export` / `volcanmig_after_export` (actions, $operation_id)

**Rationale**: A documented public surface lets advanced users tune chunking and exclusions without forking. Keeping the surface small avoids painting ourselves into compatibility corners early.

---

## NEEDS CLARIFICATION

None remain. Every input from the spec has been mapped to a decision above. The Phase 0 gate is satisfied.
