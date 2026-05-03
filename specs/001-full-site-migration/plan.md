# Implementation Plan: Volcán Migration v1.0 — Full-Site Migration vía Google Drive

**Branch**: `001-full-site-migration` | **Date**: 2026-05-03 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-full-site-migration/spec.md`

## Summary

Volcán Migration is a free GPL WordPress plugin that exports a full WordPress installation (database + selected `wp-content` directories) into a single migration archive, uploads it resumably to the user's own Google Drive, and restores it onto a target installation with safe URL/serialization rewriting and an automatic safety backup. Single-site and multisite are supported from day one. The plugin runs entirely in-process inside WordPress, never phones home, and uses the user's own Google OAuth client (Client ID/Secret).

**Technical approach** (resolved in Phase 0):

- A custom binary archive format (`.volcan`) written/streamed in fixed-size chunks (default 4 MiB) so a 5 GB site can be packed and unpacked on shared hosting (256 MB PHP, 300 s `max_execution_time`) by yielding control between chunks via WordPress's `WP_Background_Process`-style loopback (re-entrant AJAX) pattern.
- Google Drive integration via `google/apiclient` scoped under `VolcanMigration\Vendor\` with PHP-Scoper, using resumable uploads (Drive `uploadType=resumable`) and the minimal `drive.file` OAuth scope.
- OAuth refresh + access tokens stored in `wp_options` (or `wp_sitemeta` on multisite) encrypted with AES-256-GCM using a key derived from `AUTH_KEY` + `SECURE_AUTH_KEY` via HKDF-SHA256.
- URL replacement on the imported DB done with a streaming, serialization-aware rewriter that walks PHP-serialized values without unserializing untrusted strings (depth-limited tokenizer that recomputes byte lengths).
- Browser → server upload uses chunked multipart `XMLHttpRequest` so the user can import a backup from disk regardless of `upload_max_filesize` / `post_max_size`.
- One concurrent migration operation per site, enforced with a transient-based lock and resumable checkpoints persisted in a custom `wp_volcanmig_operations` table.

## Technical Context

**Language/Version**: PHP 7.4 minimum, tested through 8.3; JavaScript ES2017 for admin UI scripts (no build step beyond optional minification kept off per §IV).
**Primary Dependencies**: WordPress 6.0+ core APIs (`wpdb`, `WP_Filesystem`, `wp_remote_*`, REST/AJAX, Settings API, Background Process pattern); `google/apiclient` (only third-party Composer dep, scoped via PHP-Scoper to `VolcanMigration\Vendor\`); browser-side `fetch`/`XMLHttpRequest` with progress events; no jQuery hard dependency for new code.
**Storage**:
  - Settings, OAuth tokens (encrypted), per-site Drive folder ID, retention policy → `wp_options` (single-site) / `wp_sitemeta` (multisite-network) / `wp_NN_options` (multisite-subsite).
  - Operations + log entries → custom tables `wp_volcanmig_operations` and `wp_volcanmig_logs` (network-wide on multisite, with `blog_id` column).
  - Temporary archive parts → `wp-content/uploads/volcan-migration/tmp/<operation_id>/`.
**Testing**: PHPUnit ≥ 9 with WP test scaffold (`wp-cli scaffold plugin-tests` baseline); brainstorm fixtures for serialized PHP arrays/objects and zip-slip path attempts; integration test exporting a small site and re-importing it on a different host/domain inside a Docker fixture.
**Target Platform**: WordPress sites on shared LAMP/LEMP hosting (Linux, Apache or Nginx, PHP-FPM, MySQL 5.7+ / MariaDB 10.3+). Admin UI runs in evergreen browsers (last 2 versions of Chrome/Firefox/Safari/Edge).
**Project Type**: WordPress plugin (single deliverable: a folder named `volcan-migration/` with `volcan-migration.php` bootstrap + `src/` PHP code + `assets/` JS/CSS + `languages/` translations + `src/Vendor/` scoped third-party).
**Performance Goals**:
  - Export 5 GB site in ≤ 60 minutes wall-clock on shared hosting (256 MB / 300 s) with chunk-based loopback.
  - Resumable upload: chunk size 8 MiB to Drive; survive ≤ 30 s network blips without restarting.
  - URL replacement: ≥ 5 MB/s of DB rows scanned on a single PHP worker.
  - Admin UI: no blocking page render; all heavy work behind AJAX progress bars.
**Constraints**:
  - PHP memory ≤ 256 MB per request, `max_execution_time` ≤ 300 s — never load the full archive in memory; never `unserialize()` untrusted strings.
  - Network egress restricted to `*.googleapis.com`, `*.google.com` (OAuth), and `api.wordpress.org` (only for plugin updates served by core, not by us). Verified by audit (SC-006).
  - No Composer at runtime; no minified or obfuscated code shipped (§IV).
  - GPL-only assets; `readme.txt` must validate against WP.org's Readme Validator.
  - Anti zip-slip: every extracted path must canonicalize inside the destination root.
  - All AJAX endpoints require `manage_options` (single-site) or `manage_network_options` (multisite) + valid nonce.
**Scale/Scope**: Sites up to 5 GB end-to-end; up to ~10⁵ DB rows touched by URL replacement; up to a few thousand uploads files. UI surface ~6 admin tabs (Settings, Export, Backups, Import, Logs, Help). Code size estimate ~6–8 k LOC PHP + ~1 k LOC JS.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Gates derive from `.specify/memory/constitution.md` v1.0.0. Each gate is a binary check the design MUST satisfy.

### I. Identidad y propósito
- [x] **G-I.1** Plugin slug, text domain, namespace, and global prefix match the constitution exactly (`volcan-migration`, `VolcanMigration\`, `volcanmig_`). Verified in Project Structure below.
- [x] **G-I.2** Scope of v1.x stays within "clone full WP site via Google Drive". No scheduler, no other providers, no incremental — confirmed in spec §"Out of Scope".

### II. Licencia y modelo
- [x] **G-II.1** All shipped code and assets are GPLv2+ compatible. `google/apiclient` is Apache-2.0 (compatible with GPLv3-or-later distribution). No proprietary code embedded.
- [x] **G-II.2** No paid tier, no upsell, no telemetry. UI must contain no opt-out tracking dialogs because there is no tracking.
- [x] **G-II.3** Network egress whitelist: only `*.googleapis.com` / `*.google.com` (Drive API + OAuth) and `api.wordpress.org` (WP core handles updates). Enforced by code review + auditing test (SC-006).

### III. Compatibilidad y stack
- [x] **G-III.1** PHP ≥ 7.4 syntax only; no PHP 8 typed nullable property unions in code paths reachable from PHP 7.4. CI runs PHPUnit on 7.4, 8.0, 8.1, 8.2, 8.3.
- [x] **G-III.2** WordPress ≥ 6.0 APIs only.
- [x] **G-III.3** Multisite supported on day one — covered by US8 + FR-050…FR-052.
- [x] **G-III.4** No Composer at runtime — `src/Vendor/` is committed already-scoped. Only build-time dependency is PHP-Scoper.
- [x] **G-III.5** Only one significant external dep (`google/apiclient`). Any further dep introduced later requires justification in that feature's plan.

### IV. Compliance WP.org (no negociable)
- [x] **G-IV.1** GPL-only code/assets.
- [x] **G-IV.2** No phone home without opt-in. The plugin makes only OAuth + Drive calls explicitly initiated by the admin.
- [x] **G-IV.3** No Composer in runtime.
- [x] **G-IV.4** All vendor namespaces scoped via PHP-Scoper.
- [x] **G-IV.5** Plugin Check passes with zero warnings — wired into CI.
- [x] **G-IV.6** `readme.txt` written in WP.org format (not Markdown) and validated.
- [x] **G-IV.7** Plugin name does not start with "WP" or "WordPress".
- [x] **G-IV.8** No minification or obfuscation in distributed sources.
- [x] **G-IV.9** No generic frameworks duplicating WP core.

### V. Seguridad (no negociable)
- [x] **G-V.1** Every admin action calls `current_user_can('manage_options')` (or `'manage_network_options'` on multisite) AND `check_admin_referer` / `check_ajax_referer` on a feature-specific nonce.
- [x] **G-V.2** All input goes through `sanitize_text_field` / `esc_url_raw` / `absint` / `wp_kses` as appropriate.
- [x] **G-V.3** All output is escaped (`esc_html`, `esc_attr`, `esc_url`).
- [x] **G-V.4** All SQL uses `$wpdb->prepare()`. Custom-table writers use `$wpdb->insert/update/delete` (which prepare internally).
- [x] **G-V.5** Path validation in archive extractor canonicalizes every entry against destination root; rejects `../`, absolute paths, and symlinks pointing outside.
- [x] **G-V.6** OAuth tokens encrypted at rest with key derived from `AUTH_KEY`+`SECURE_AUTH_KEY`. Tokens rotate; refresh token re-encrypted on rotation.
- [x] **G-V.7** Logs scrub tokens, passwords, and serialized values; logger has an explicit redaction list.
- [x] **G-V.8** `defined('ABSPATH') || exit;` at the top of every PHP file (enforced by PHPCS sniff in CI).
- [x] **G-V.9** Automatic DB safety backup BEFORE any destructive import action. Restore link offered on failure.

### VI. Calidad de código
- [x] **G-VI.1** PHPCS with `WordPress` ruleset green in CI.
- [x] **G-VI.2** PHPStan level ≥ 5 green in CI.
- [x] **G-VI.3** PSR-4 autoloading via the plugin's own autoloader (no Composer at runtime).
- [x] **G-VI.4** No `error_log()`, `var_dump`, `print_r`, `die()` in shipped code (PHPCS custom sniff or grep gate).
- [x] **G-VI.5** Comments in English; UI strings translatable via `__()` / `_e()` / `esc_html__` with text domain `volcan-migration`.
- [x] **G-VI.6** Unit tests for `Database`, `Archiver`, `UrlReplacer`, `ChunkedUploader` ≥ 70% coverage each (CI fails below).

  Constitution test target → Concrete class:
  - "Database"        → `Export\DatabaseDumper` + `Import\DatabaseRestorer`
  - "Archiver"        → `Archive\VolcanWriter` + `Archive\VolcanReader`
  - "UrlReplacer"     → `Import\UrlReplacer`
  - "ChunkedUploader" → `Drive\ResumableUploader`
- [x] **G-VI.7** End-to-end integration test: export → import on a small fixture site.

### VII. Internacionalización
- [x] **G-VII.1** Source language `en_US`. No hardcoded UI strings.
- [x] **G-VII.2** Priority locales `es_AR`, `es_ES`, `pt_BR` shipped under `languages/`.
- [x] **G-VII.3** `.pot` regenerated by CI on every release tag.

### VIII. Privacidad y datos del usuario
- [x] **G-VIII.1** Zero data collection by the plugin (no analytics, no opt-in either, since none is needed).
- [x] **G-VIII.2** OAuth uses the user's own Client ID/Secret. Author never sees credentials.
- [x] **G-VIII.3** Backups stored only on user's filesystem and user's Drive — never on author-controlled infra.
- [x] **G-VIII.4** Privacy declaration shipped in `readme.txt`.

### IX. Workflow de desarrollo
- [x] **G-IX.1** Spec-Driven Development followed (`constitution → specify → plan → tasks → implement`). This is the `plan` artifact.
- [x] **G-IX.2** Repo public on GitHub from day one.
- [x] **G-IX.3** Conventional Commits enforced via commitlint or PR template.
- [x] **G-IX.4** GitHub Actions CI: PHPCS, PHPStan, Plugin Check, PHPUnit.
- [x] **G-IX.5** Releases tagged semver.

### X. Lo que el plugin NO hace
- [x] **G-X.1** No incremental backups in v1.x.
- [x] **G-X.2** Drive-only — no Dropbox/S3/OneDrive provider abstractions.
- [x] **G-X.3** No staging system, no centralized multi-site dashboard.
- [x] **G-X.4** No cloud control panel. No paid addons.
- [x] **G-X.5** No major-version cross-WP upgrade — import refuses an archive whose source WP major differs from destination's.

### XI. Definición de "listo"
- [x] **G-XI.1** Each feature task closes only when PHPCS + PHPStan + Plugin Check + PHPUnit are green.
- [x] **G-XI.2** Strings translatable, `readme.txt` and `CHANGELOG.md` updated, `.pot` regenerated.
- [x] **G-XI.3** Manual smoke test on at least one real site (recorded in PR description).
- [x] **G-XI.4** No secrets, no debug, no dead code.

**Initial Constitution Check verdict**: PASS — no gate violations; no entries needed in Complexity Tracking.

**Post-Design Re-evaluation (after Phase 1)**: PASS — research.md, data-model.md, contracts/, and quickstart.md introduce no new dependencies, no telemetry, no shell-only steps, no Composer-at-runtime, no minified output, no unscoped vendor namespaces. The custom binary archive format (R2), HKDF-AES-GCM token cipher (R4), serialization-safe URL replacer (R6), and re-entrant AJAX tick driver (R1) all stay inside §III–§VI bounds. Multisite handling (R8) and the per-site OperationLock (R9) honor §III.3 and §V.1. No additions to Complexity Tracking required.

## Project Structure

### Documentation (this feature)

```text
specs/001-full-site-migration/
├── plan.md              # This file (/speckit-plan output)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (REST/AJAX action contracts)
│   ├── settings.md
│   ├── oauth.md
│   ├── export.md
│   ├── upload.md
│   ├── backups.md
│   ├── import.md
│   ├── pc-upload.md
│   └── logs.md
├── spec.md              # Existing feature specification
└── tasks.md             # Phase 2 output (created by /speckit-tasks)
```

### Source Code (repository root)

```text
volcan-migration/                     # Plugin root (also the SVN trunk and zip name)
├── volcan-migration.php              # Bootstrap: plugin header, ABSPATH guard, autoloader
├── uninstall.php                     # Remove options/tables on full uninstall
├── readme.txt                        # WP.org format readme (validated)
├── CHANGELOG.md
├── LICENSE                           # GPLv2-or-later
├── languages/
│   ├── volcan-migration.pot
│   ├── volcan-migration-es_AR.po
│   ├── volcan-migration-es_ES.po
│   └── volcan-migration-pt_BR.po
├── assets/
│   ├── js/
│   │   ├── admin-settings.js
│   │   ├── admin-export.js
│   │   ├── admin-import.js
│   │   ├── admin-backups.js
│   │   ├── admin-pc-upload.js
│   │   └── progress-poller.js        # Shared chunked-progress AJAX helper
│   └── css/
│       └── admin.css
├── src/                              # PSR-4 root for VolcanMigration\
│   ├── Plugin.php                    # Service container + bootstrap
│   ├── Activator.php                 # Activation hook (create tables, defaults)
│   ├── Deactivator.php
│   ├── Admin/
│   │   ├── Menu.php                  # Registers admin pages (single + network)
│   │   ├── Capability.php            # Single-vs-multisite capability resolver
│   │   ├── Pages/
│   │   │   ├── SettingsPage.php
│   │   │   ├── ExportPage.php
│   │   │   ├── BackupsPage.php
│   │   │   ├── ImportPage.php
│   │   │   └── LogsPage.php
│   │   └── Notices.php
│   ├── Ajax/                         # All admin-ajax endpoints (one per action)
│   │   ├── AjaxHandler.php           # Base: capability + nonce + JSON response
│   │   ├── SaveCredentials.php
│   │   ├── ConnectDrive.php
│   │   ├── DisconnectDrive.php
│   │   ├── DriveStatus.php
│   │   ├── ExportStart.php
│   │   ├── ExportTick.php            # Re-entrant per-chunk worker
│   │   ├── ExportCancel.php
│   │   ├── UploadStart.php
│   │   ├── UploadTick.php
│   │   ├── UploadCancel.php
│   │   ├── BackupsList.php
│   │   ├── BackupDelete.php
│   │   ├── BackupDownload.php
│   │   ├── ImportStart.php
│   │   ├── ImportTick.php
│   │   ├── ImportCancel.php
│   │   ├── ImportRestoreSafety.php
│   │   ├── PcUploadInit.php
│   │   ├── PcUploadChunk.php
│   │   ├── PcUploadFinalize.php
│   │   └── LogsList.php
│   ├── OAuth/
│   │   ├── ClientFactory.php         # Wraps google/apiclient with the user's creds
│   │   ├── TokenStore.php            # Encrypted load/save in options
│   │   ├── Cipher.php                # AES-256-GCM + HKDF over AUTH_KEY+SECURE_AUTH_KEY
│   │   └── CallbackHandler.php       # Handles ?volcanmig_oauth_callback=1
│   ├── Drive/
│   │   ├── DriveClient.php           # Thin wrapper exposing only the calls we use
│   │   ├── ResumableUploader.php     # 8 MiB chunks, retry w/ exponential backoff
│   │   ├── FolderResolver.php        # Find/create per-site folder; relocate by ID
│   │   └── QuotaChecker.php
│   ├── Export/
│   │   ├── Exporter.php              # Orchestrator (state machine via Operation)
│   │   ├── DatabaseDumper.php        # Streamed mysqldump-style writer, serialization-safe
│   │   ├── FileCollector.php         # Streams uploads/themes/plugins/mu-plugins
│   │   └── ManifestBuilder.php       # Generates manifest.json (versions, prefixes, hashes)
│   ├── Archive/
│   │   ├── VolcanWriter.php          # Custom binary archive writer (chunk-streaming)
│   │   ├── VolcanReader.php          # Streaming reader
│   │   └── PathGuard.php             # Anti zip-slip canonicalizer
│   ├── Import/
│   │   ├── Importer.php              # Orchestrator (state machine)
│   │   ├── SafetyBackup.php          # Pre-import DB safety dump
│   │   ├── DatabaseRestorer.php
│   │   ├── FileRestorer.php
│   │   ├── UrlReplacer.php           # Serialization-safe URL rewriter
│   │   ├── PrefixAdjuster.php        # Rewrites table prefixes when origin ≠ dest
│   │   └── VersionGuard.php          # Refuses major-WP-version mismatches
│   ├── Operation/
│   │   ├── Operation.php             # DTO
│   │   ├── OperationRepository.php   # CRUD on wp_volcanmig_operations
│   │   ├── OperationLock.php         # Transient-based single-op-per-site lock
│   │   └── Status.php                # Enum-like: pending/running/completed/cancelled/failed
│   ├── Log/
│   │   ├── Logger.php                # PSR-3-shaped, persists to wp_volcanmig_logs
│   │   ├── Redactor.php              # Strip secrets/tokens/PII before persist
│   │   └── Rotator.php               # Retention policy: 90 days OR 50 ops, whichever first
│   ├── Filesystem/
│   │   ├── TempDir.php               # uploads/volcan-migration/tmp/<op_id>/
│   │   └── ChunkBuffer.php
│   ├── Support/
│   │   ├── Hooks.php                 # `volcanmig_*` hook registry
│   │   ├── BackgroundLoopback.php    # Re-entrant AJAX tick driver
│   │   └── Autoloader.php            # PSR-4 autoloader for VolcanMigration\
│   └── Vendor/                       # PHP-Scoper output (committed pre-built)
│       └── google/apiclient/...
├── tests/
│   ├── bootstrap.php
│   ├── unit/
│   │   ├── ArchiveTest.php
│   │   ├── DatabaseDumperTest.php
│   │   ├── UrlReplacerTest.php
│   │   ├── ChunkedUploaderTest.php
│   │   ├── PathGuardTest.php         # Zip-slip fixtures
│   │   ├── CipherTest.php
│   │   └── PrefixAdjusterTest.php
│   ├── integration/
│   │   ├── ExportImportRoundTripTest.php
│   │   └── MultisiteSubsiteRoundTripTest.php
│   └── fixtures/
│       ├── serialized/               # Nested arrays/objects/encoded URLs
│       └── archives/
└── tools/
    ├── scoper.inc.php                # PHP-Scoper config
    └── build-release.sh              # Produces zip + .pot, no minification
```

**Structure Decision**: This is a single-deliverable WordPress plugin, so we use the standard plugin layout (Option 1, single project) with all code under `volcan-migration/src/` (PSR-4 root for the `VolcanMigration\` namespace) and the third-party `google/apiclient` pre-scoped into `volcan-migration/src/Vendor/`. Tests live alongside under `volcan-migration/tests/`. There is no separate frontend/backend split because the admin UI ships as part of the plugin and runs inside `wp-admin`.

## Complexity Tracking

> No constitution gate violations. Section intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| _(none)_  | _(none)_   | _(none)_                            |
