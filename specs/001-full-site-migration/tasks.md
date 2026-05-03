---
description: "Implementation tasks for Volcán Migration v1.0 — Full-Site Migration vía Google Drive"
---

# Tasks: Volcán Migration v1.0 — Full-Site Migration vía Google Drive

**Input**: Design documents from `/specs/001-full-site-migration/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md
**Tests**: Included — Constitution §VI.6 mandates unit tests for `Database`, `Archiver`, `UrlReplacer`, `ChunkedUploader` (≥70% coverage; ≥90% on `UrlReplacer`) plus an export→import integration test.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks).
- **[Story]**: User story tag (US1…US9), required only inside user-story phases.
- All paths are relative to repo root. The plugin folder is `volcan-migration/`.
- **Note**: Task IDs may include a lowercase letter suffix (e.g., `T011a`, `T102b`) when tasks are inserted between existing IDs during remediation cycles. The suffix preserves relative ordering without renumbering downstream tasks.

## Path Conventions

Single-deliverable WordPress plugin per `plan.md` §"Project Structure":

- Plugin code: `volcan-migration/src/...` (PSR-4 root for `VolcanMigration\`)
- Plugin assets: `volcan-migration/assets/...`
- Tests: `volcan-migration/tests/{unit,integration,fixtures}/`
- Tooling: `tools/...` and `.github/workflows/...` at repo root

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project skeleton, build/CI tooling, and the vendored Google API client. No business logic.

- [ ] T001 Create plugin folder skeleton at `volcan-migration/` with subdirectories `src/`, `assets/js/`, `assets/css/`, `languages/`, `tests/{unit,integration,fixtures/serialized,fixtures/archives}/`
- [ ] T002 Create plugin bootstrap `volcan-migration/volcan-migration.php` with WP plugin header (Name "Volcán Migración", Slug `volcan-migration`, Text Domain `volcan-migration`, License GPLv2-or-later), `defined('ABSPATH') || exit;`, and a require of the autoloader
- [ ] T003 [P] Implement PSR-4 autoloader at `volcan-migration/src/Support/Autoloader.php` (registers `VolcanMigration\` → `src/`, `VolcanMigration\Vendor\` → `src/Vendor/`)
- [ ] T004 [P] Add `LICENSE` (GPLv2-or-later) at repo root
- [ ] T005 [P] Add `volcan-migration/CHANGELOG.md` with a "[Unreleased]" section
- [ ] T006 [P] Add `volcan-migration/readme.txt` skeleton in WP.org format (sections: Description, Installation, FAQ, Changelog, Privacy, ≤ 150-char tagline)
- [ ] T007 [P] Add `.gitignore` (PHP, IDE, build artifacts) and `volcan-migration/.distignore` (excludes tests/, tools/, dev configs from packaged zip)
- [ ] T008 [P] Add dev `composer.json` at repo root (dev-only: `php-scoper`, `squizlabs/php_codesniffer`, `wp-coding-standards/wpcs`, `phpstan/phpstan`, `phpunit/phpunit:^9`, `yoast/phpunit-polyfills`); include comment that runtime has no Composer
- [ ] T009 [P] Add `tools/scoper.inc.php` mapping `Google\`, `GuzzleHttp\`, `Psr\`, `Firebase\` → prefix `VolcanMigration\Vendor\`; exclude WordPress functions
- [ ] T010 [P] Add `tools/build-release.sh` that runs `composer install --no-dev`, `php-scoper add-prefix`, strips dev files, regenerates `.pot`, and produces `dist/volcan-migration.zip`
- [ ] T011 [P] Add `phpcs.xml.dist` at repo root referencing `WordPress` ruleset, scanning `volcan-migration/src/` and `volcan-migration/tests/`
- [ ] T011a [P] Add `.github/PULL_REQUEST_TEMPLATE.md` and `.github/COMMIT_CONVENTION.md` enforcing Conventional Commits per Constitution §IX.3 (`feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, `style`). Link `COMMIT_CONVENTION.md` from the repo's main `README.md`.
- [ ] T012 [P] Add `phpstan.neon.dist` at repo root with `level: 5`, `paths: [volcan-migration/src]`, WordPress stubs via `szepeviktor/phpstan-wordpress`
- [ ] T013 [P] Add `phpunit.xml.dist` and `volcan-migration/tests/bootstrap.php` (loads WP test scaffold, then plugin autoloader)
- [ ] T014 [P] Add `.github/workflows/ci.yml` running PHPCS, PHPStan, PHPUnit (matrix PHP 7.4/8.0/8.1/8.2/8.3), and the official `wordpress/plugin-check-action`
- [ ] T014a [P] In `.github/workflows/ci.yml`, add a `forbidden-functions-check` step that fails the build if any debug call slipped into shipped code (Constitution §VI.4). Implementation:
    ```bash
    ! grep -rE "\b(error_log|var_dump|print_r|die|dd)\s*\(" volcan-migration/src/ --include="*.php"
    ```
  The negated `grep` exits non-zero when matches are found, which fails the step. The path is `volcan-migration/src/` only — `volcan-migration/tests/` is intentionally not scanned.
- [ ] T015 Run PHP-Scoper to populate `volcan-migration/src/Vendor/` with scoped `google/apiclient` + transitive deps; commit the scoped output

**Checkpoint**: `composer install`, `phpcs`, `phpstan`, and `phpunit` all run without errors against an empty plugin.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Primitives every user story depends on — service container, custom tables, security primitives, operation infra, logger, AJAX base, admin menu shell.

**⚠️ CRITICAL**: No user story work begins until this phase is complete.

### Service container & lifecycle

- [ ] T016 Create `volcan-migration/src/Plugin.php` — service container, registers hooks on `plugins_loaded` and `admin_menu`, exposes `Plugin::instance()`
- [ ] T020 Create `volcan-migration/src/Schema/Installer.php` implementing the `wp_volcanmig_operations` and `wp_volcanmig_logs` schemas from `data-model.md` §5/§6 (called by `Activator`)
- [ ] T017 Create `volcan-migration/src/Activator.php` — `register_activation_hook` callback: invoke `Schema/Installer`, set defaults for `volcanmig_settings`, schedule cron events. **Depends on T020** (Schema/Installer must exist).
- [ ] T018 [P] Create `volcan-migration/src/Deactivator.php` — unschedules cron events; preserves data
- [ ] T019 [P] Create `volcan-migration/uninstall.php` — drops custom tables, deletes plugin options (oauth_tokens, settings, locks, pc_upload sessions), removes `wp-content/uploads/volcan-migration/`

### Security primitives

- [ ] T021 [P] Create `volcan-migration/src/OAuth/Cipher.php` — AES-256-GCM with HKDF-SHA256 over `AUTH_KEY+SECURE_AUTH_KEY`, `key_version` field, `encrypt()`/`decrypt()`, base64 wrapper; prefer `sodium_*` when available
- [ ] T022 [P] Create `volcan-migration/src/Archive/PathGuard.php` — canonicalize entries against destination root, reject `..`, absolute paths, symlinks pointing outside
- [ ] T023 [P] Create `volcan-migration/src/Admin/Capability.php` — `current()` returns `manage_options` or `manage_network_options` depending on `is_multisite()` + network-admin context; `require()` aborts with `wp_send_json_error('forbidden', 403)` when missing

### Operation infrastructure

- [ ] T024 [P] Create `volcan-migration/src/Operation/Status.php` — string-enum-like constants (`PENDING`, `RUNNING`, `COMPLETED`, `CANCELLED`, `FAILED`)
- [ ] T025 [P] Create `volcan-migration/src/Operation/Operation.php` — DTO with all `wp_volcanmig_operations` fields + `state_json` typed accessors
- [ ] T026 Create `volcan-migration/src/Operation/OperationRepository.php` — CRUD on the table; `transition($id, $next)` enforcing the state machine from `data-model.md` §5.2
- [ ] T027 Create `volcan-migration/src/Operation/OperationLock.php` — `add_option`/`add_site_option`-based CAS, heartbeat update, stale lock reaper after `tick_budget × 4`
- [ ] T028 [P] Create `volcan-migration/src/Filesystem/TempDir.php` — resolves `wp-content/uploads/volcan-migration/tmp/<op_id>/`; writes `.htaccess` deny + `index.html` stub on first use
- [ ] T029 [P] Create `volcan-migration/src/Filesystem/ChunkBuffer.php` — fixed-size buffered append helper used by chunked writers/readers

### Logger

- [ ] T030 [P] Create `volcan-migration/src/Log/Redactor.php` — strips values whose keys match `/(token|secret|password|access[_-]?key|client[_-]?secret)/i` and adjacent base64 ≥ 32 chars
- [ ] T031 Create `volcan-migration/src/Log/Logger.php` — PSR-3-shaped, persists to `wp_volcanmig_logs`, applies Redactor on every write, level filtered by `WP_DEBUG`
- [ ] T032 Create `volcan-migration/src/Log/Rotator.php` — daily WP-Cron `volcanmig_logs_gc` callback enforcing retention (90 days OR 50 ops per blog)

### AJAX & background loop

- [ ] T033 [P] Create `volcan-migration/src/Support/Hooks.php` — declares the public `volcanmig_*` filter/action surface from `research.md` R12
- [ ] T034 Create `volcan-migration/src/Support/BackgroundLoopback.php` — re-entrant tick driver: 25s budget, 70% memory ceiling, persists checkpoints, honors cancellation
- [ ] T035 Create `volcan-migration/src/Ajax/AjaxHandler.php` — abstract base: `handle()` that runs Capability::require → `check_ajax_referer` → input validation → dispatch → JSON response with consistent error codes

### Admin shell (UI scaffolding only — pages filled per US)

- [ ] T036 [P] Create `volcan-migration/src/Admin/Menu.php` — registers top-level menu, sub-menus (Settings, Export, Backups, Import, Logs, Help), and network-admin equivalents
- [ ] T037 [P] Create `volcan-migration/src/Admin/Notices.php` — admin_notices renderer keyed by transient
- [ ] T038 [P] Create `volcan-migration/src/Admin/Pages/AbstractPage.php` — base view with header, tabs, nonce printer, JSON localization helper

### Cron events & temp GC

- [ ] T039 Wire activation cron events: `volcanmig_logs_gc` (daily), `volcanmig_tmp_gc` (daily, removes orphan temp dirs), `volcanmig_pc_upload_gc` (daily, drops idle PC upload sessions)

### Foundational tests

- [ ] T040 [P] Unit test `volcan-migration/tests/unit/CipherTest.php` — round-trip, key versioning, GCM tag tampering rejection, key-rotation invalidation
- [ ] T041 [P] Unit test `volcan-migration/tests/unit/PathGuardTest.php` — fixture vectors for `..`, absolute paths, symlinks, encoded traversal, Windows-style separators
- [ ] T042 [P] Unit test `volcan-migration/tests/unit/OperationLockTest.php` — concurrent acquire returns false, heartbeat refresh, stale-lock reap
- [ ] T043 [P] Unit test `volcan-migration/tests/unit/RedactorTest.php` — token/secret/password keys, adjacent base64 blobs, nested arrays
- [ ] T044 [P] Unit test `volcan-migration/tests/unit/OperationRepositoryTest.php` — illegal state transitions raise; legal ones persist

**Checkpoint**: All foundational tests green; all stories may now begin.

---

## Phase 3: User Story 1 — Configurar el plugin (Priority: P1) 🎯 MVP gate

**Goal**: An admin can land on the Settings page, paste Client ID/Secret, and see the connection status surface.

**Independent Test**: On a clean activation, navigate to Settings, save credentials, see "Conectar Drive" become enabled and credentials persist after reload.

### Tests for User Story 1

- [ ] T045 [P] [US1] Unit test `volcan-migration/tests/unit/TokenStoreTest.php` — credentials round-trip, invalidation when Client ID changes, decrypt failure on key rotation

### Implementation for User Story 1

- [ ] T046 [P] [US1] Create `volcan-migration/src/OAuth/TokenStore.php` — load/save the encrypted blob in `volcanmig_oauth_tokens` (option/sitemeta), payload schema from `data-model.md` §3
- [ ] T047 [P] [US1] Create `volcan-migration/src/Admin/Pages/SettingsPage.php` — renders form (Client ID, Secret), connection status, quota panel placeholder, all strings translatable
- [ ] T048 [P] [US1] Create `volcan-migration/assets/js/admin-settings.js` — submits credentials via AJAX, updates UI from `volcanmig_get_status`
- [ ] T049 [P] [US1] Create `volcan-migration/assets/css/admin.css` (initial) — settings tab styles
- [ ] T050 [US1] Create `volcan-migration/src/Ajax/SaveCredentials.php` — implements contract `contracts/settings.md` `volcanmig_save_credentials` (validates Client ID regex, persists via TokenStore, invalidates existing connection)
- [ ] T051 [US1] Create `volcan-migration/src/Ajax/ClearCredentials.php` — `volcanmig_clear_credentials` (refuses while connected)
- [ ] T052 [US1] Create `volcan-migration/src/Ajax/DriveStatus.php` (lite version) — returns `{credentials_present, connected:false}` until US2 wires Drive
- [ ] T053 [US1] Register all US1 AJAX actions and SettingsPage in `Plugin.php` boot

**Checkpoint**: US1 acceptance scenarios 1–4 from spec.md pass; US2 may now begin.

---

## Phase 4: User Story 2 — Conectar Google Drive (Priority: P1)

**Goal**: Admin completes Google's OAuth consent and the plugin shows account email + Drive quota and persists tokens encrypted at rest.

**Independent Test**: Click "Conectar Drive", approve consent in Google's screen, return to settings, verify status "Conectado a `<email>`" persists across reloads, then "Desconectar" revokes and clears.

### Tests for User Story 2

- [ ] T054 [P] [US2] Integration test `volcan-migration/tests/integration/OAuthFlowTest.php` — token-exchange happy path, refresh on expiry, revoke on disconnect (using mocked HTTP)
- [ ] T055 [P] [US2] Unit test `volcan-migration/tests/unit/ClientFactoryTest.php` — scope hardcoded to `drive.file`, redirect URI built correctly

### Implementation for User Story 2

- [ ] T056 [P] [US2] Create `volcan-migration/src/OAuth/ClientFactory.php` — wraps `VolcanMigration\Vendor\Google\Client`, applies user's creds, hardcodes scope `drive.file`, sets `access_type=offline&prompt=consent`
- [ ] T057 [P] [US2] Create `volcan-migration/src/Drive/DriveClient.php` — thin wrapper exposing only `about.get`, `files.list`, `files.create`, `files.delete`, `files.get`, resumable upload helpers; injects token refresh hook
- [ ] T058 [P] [US2] Create `volcan-migration/src/Drive/QuotaChecker.php` — calls `about.get(fields=storageQuota)`, returns `used`/`limit`
- [ ] T059 [US2] Create `volcan-migration/src/Ajax/OauthStart.php` — implements `contracts/oauth.md` `volcanmig_oauth_start`, stores `state` in 10-minute transient
- [ ] T060 [US2] Create `volcan-migration/src/OAuth/CallbackHandler.php` — `admin_init` handler for `?volcanmig_oauth_callback=1`, validates state, exchanges code, persists tokens via TokenStore, redirects with success/error notice
- [ ] T061 [US2] Create `volcan-migration/src/Ajax/Disconnect.php` — `volcanmig_disconnect` (best-effort token revoke + local wipe, preserve creds)
- [ ] T062 [US2] Update `volcan-migration/src/Ajax/DriveStatus.php` to include `account_email`, `drive_quota`, `drive_folder_name`
- [ ] T063 [US2] Update `volcan-migration/src/Admin/Pages/SettingsPage.php` to render connected state (account email, quota bar, "Desconectar" button)
- [ ] T064 [US2] Wire transparent token refresh into `DriveClient` so any 401 retries once with refreshed access token

**Checkpoint**: US2 acceptance scenarios 1–4 pass. US3, US4, US5, US6 unlocked.

---

## Phase 5: User Story 3 — Exportar el sitio completo (Priority: P1)

**Goal**: Admin runs an export that produces a single `.volcan` archive locally with chunked progress, optional exclusions, and safe cancellation.

**Independent Test**: Launch export on a test site with known content; observe progress; verify the resulting archive contains DB + included `wp-content` directories and is downloadable from disk.

### Tests for User Story 3

- [ ] T065 [P] [US3] Unit test `volcan-migration/tests/unit/VolcanWriterTest.php` — sequential write, header magic, manifest parse, sha256/crc32 verification, chunk boundaries
- [ ] T066 [P] [US3] Unit test `volcan-migration/tests/unit/DatabaseDumperTest.php` — chunked output for fixture tables, row offset resumption, no `LOCK TABLES` left dangling
- [ ] T067 [P] [US3] Unit test `volcan-migration/tests/unit/ManifestBuilderTest.php` — captures wp_version, db_prefix, site_url, included sets, total bytes
- [ ] T068 [P] [US3] Unit test `volcan-migration/tests/unit/FileCollectorTest.php` — chunked streaming over a fixture directory, exclusion honors

### Implementation for User Story 3

- [ ] T069 [P] [US3] Create `volcan-migration/src/Archive/VolcanWriter.php` — implements the `VOLCAN1\n` format from `research.md` R2 (streaming append, sha256/crc32 per entry, terminator)
- [ ] T070 [P] [US3] Create `volcan-migration/src/Export/DatabaseDumper.php` — chunked writer using `$wpdb->prepare` (`SELECT … LIMIT … OFFSET …`), persists row-offset between ticks, never `unserialize`s
- [ ] T071 [P] [US3] Create `volcan-migration/src/Export/FileCollector.php` — chunked reader for `uploads`, `themes`, `plugins`, `mu-plugins` honoring per-set toggles; respects `volcanmig_export_excluded_paths` filter; **excludes `wp-config.php` by default** per FR-015
- [ ] T072 [P] [US3] Create `volcan-migration/src/Export/ManifestBuilder.php` — emits `manifest.json` (wp_version, db_prefix, site_url, home_url, included sets, total bytes, plugin version)
- [ ] T073 [US3] Create `volcan-migration/src/Export/Exporter.php` — orchestrator/state-machine consuming Operation state per `data-model.md` §5.3
- [ ] T074 [US3] Create `volcan-migration/src/Ajax/ExportStart.php` — implements `contracts/export.md` `volcanmig_export_start` (lock, persist Operation row, return id)
- [ ] T075 [US3] Create `volcan-migration/src/Ajax/ExportTick.php` — runs one tick via `BackgroundLoopback`, returns progress JSON
- [ ] T076 [US3] Create `volcan-migration/src/Ajax/ExportCancel.php` — sets cancel flag; janitor removes `tmp/<op_id>/`
- [ ] T077 [P] [US3] Create `volcan-migration/src/Admin/Pages/ExportPage.php` — UI with include-set checkboxes, progress bar, current-step label, cancel button
- [ ] T078 [P] [US3] Create `volcan-migration/assets/js/progress-poller.js` — shared 2s polling helper with exponential backoff
- [ ] T079 [P] [US3] Create `volcan-migration/assets/js/admin-export.js` — wires ExportPage to start/tick/cancel using progress-poller
- [ ] T080 [US3] Wire all US3 AJAX endpoints + ExportPage into `Plugin.php` boot

**Checkpoint**: US3 acceptance scenarios 1–5 pass. US4 unlocked.

---

## Phase 6: User Story 4 — Subir el backup al Drive (Priority: P1)

**Goal**: Archive uploads resumably to a per-site Drive folder with progress, retry, and pre-flight quota check.

**Independent Test**: Export a small (~50 MB) archive and verify it appears in the per-site Drive folder. Repeat with a larger file while interrupting network for ≤ 30 s and verify resume.

### Tests for User Story 4

- [ ] T081 [P] [US4] Unit test `volcan-migration/tests/unit/ResumableUploaderTest.php` — handles 308 with `Range` header, retries on 5xx with exponential backoff, refreshes token on 401, cancels via `DELETE` on session URL
- [ ] T082 [P] [US4] Unit test `volcan-migration/tests/unit/FolderResolverTest.php` — finds existing folder by `appProperties.volcanmig_site_key`, creates one when missing, relocates by ID after manual move
- [ ] T083 [P] [US4] Integration test `volcan-migration/tests/integration/UploadResumeTest.php` — small upload survives a simulated 30 s disconnect mid-stream

### Implementation for User Story 4

- [ ] T084 [P] [US4] Create `volcan-migration/src/Drive/FolderResolver.php` — find-or-create per-site folder; tag with `appProperties.volcanmig_site_key`; cache folder ID
- [ ] T085 [P] [US4] Create `volcan-migration/src/Drive/ResumableUploader.php` — 8 MiB chunks, `Content-Range` headers, persists `drive_session_url` on the Operation row (encrypted), backoff `1,2,4,8,16` s
- [ ] T086 [US4] Create `volcan-migration/src/Ajax/UploadStart.php` — implements `contracts/upload.md` `volcanmig_upload_start`: pre-flight quota via `QuotaChecker`, open Drive resumable session, persist URL
- [ ] T087 [US4] Create `volcan-migration/src/Ajax/UploadTick.php` — pushes one chunk per tick, tracks `bytes_done`/`progress_pct`, applies retry/backoff
- [ ] T087a [US4] In `volcan-migration/assets/js/admin-export.js` and `volcan-migration/assets/js/admin-pc-upload.js`, implement transfer-speed calculation via EWMA (exponential weighted moving average, smoothing factor 0.3) over the byte deltas observed in each progress poll. Render as `${value.toFixed(1)} MiB/s` next to the percentage. No contract change required to `UploadTick` — the calculation is fully client-side, derived from `bytes_done` + `Date.now()`.
- [ ] T088 [US4] Create `volcan-migration/src/Ajax/UploadCancel.php` — `DELETE` Drive session, mark cancelled, free lock
- [ ] T089 [US4] On upload success, set Drive `appProperties` per `data-model.md` §7 (volcanmig_version, site_key, wp_version, db_prefix, size_bytes, sha256)
- [ ] T090 [US4] Update `volcan-migration/src/Admin/Pages/ExportPage.php` to surface "Subir a Drive" CTA after a successful export
- [ ] T091 [P] [US4] Update `volcan-migration/assets/js/admin-export.js` to chain into upload polling

**Checkpoint**: US4 acceptance scenarios 1–5 pass.

---

## Phase 7: User Story 5 — Listar y gestionar backups en Drive (Priority: P1)

**Goal**: Admin sees all backups in the per-site Drive folder with download/delete/import affordances.

**Independent Test**: With ≥ 2 backups already in the folder, open Backups tab, verify list with name/date/size; download one; delete one; see empty state when folder is empty.

### Tests for User Story 5

- [ ] T092 [P] [US5] Unit test `volcan-migration/tests/unit/BackupsListTest.php` — normalizes Drive `files.list` response, computes `site_key_match`, paginates via `pageToken`

### Implementation for User Story 5

- [ ] T093 [P] [US5] Create `volcan-migration/src/Admin/Pages/BackupsPage.php` — table view with sort by date desc, action buttons, empty state
- [ ] T094 [P] [US5] Create `volcan-migration/assets/js/admin-backups.js` — fetches list, renders rows, wires buttons, confirmation dialog for delete
- [ ] T095 [US5] Create `volcan-migration/src/Ajax/BackupsList.php` — implements `contracts/backups.md` `volcanmig_backups_list`
- [ ] T096 [US5] Create `volcan-migration/src/Ajax/BackupDelete.php` — verifies file lives inside per-site folder, `files.delete` skipping trash
- [ ] T097 [US5] Create `volcan-migration/src/Ajax/BackupDownload.php` — streams via `fpassthru` for ≤ 2 GB; for larger, returns short-lived `webContentLink` redirect

**Checkpoint**: US5 acceptance scenarios 1–5 pass.

---

## Phase 8: User Story 6 — Importar un backup desde Drive (Priority: P1)

**Goal**: Admin restores a backup onto the current install with auto safety backup, serialization-safe URL replacement, prefix adjustment, and recovery offer on failure.

**Independent Test**: Take a backup of site A and restore it on site B with a different domain/subdirectory; verify site B is functional at first login with internal links pointing to the new URL.

### Tests for User Story 6

- [ ] T098 [P] [US6] Unit test `volcan-migration/tests/unit/UrlReplacerTest.php` — ≥ 90% coverage; fixtures from `tests/fixtures/serialized/` (nested arrays, `stdClass`, custom-class objects, encoded URLs, URL chains); never invokes `unserialize` on input
- [ ] T099 [P] [US6] Unit test `volcan-migration/tests/unit/PrefixAdjusterTest.php` — rewrites table prefixes, leaves non-prefix tables untouched
- [ ] T100 [P] [US6] Unit test `volcan-migration/tests/unit/VersionGuardTest.php` — refuses cross-major WP migration, allows same-major
- [ ] T101 [P] [US6] Unit test `volcan-migration/tests/unit/VolcanReaderTest.php` — sequential read, sha256/crc32 verification, malformed-archive rejection
- [ ] T101a [P] [US6] Unit test `volcan-migration/tests/unit/Archive/MalformedArchiveRejectionTest.php` covering each malformed-archive vector (with corrupt fixtures committed under `volcan-migration/tests/fixtures/malformed-archives/`):
    - bad magic bytes in header → reject with code `invalid_format`
    - file truncated mid-entry → reject with `truncated`
    - declared length larger than payload → reject with `length_mismatch`
    - declared SHA256 differs from computed → reject with `checksum_mismatch`
  Each case asserts `VolcanReader::open()` throws a typed exception carrying the code AND that the message is i18n-ready (passes through `__()` with the `volcan-migration` text domain).
- [ ] T102a [P] [US6] Integration test `volcan-migration/tests/integration/ExportImportRoundTripSameUrlTest.php` — export on a site with URL X → import on a clean site with the same URL X. Asserts that posts, options, uploads, and active plugins are byte-identical to the source. Fixture: `volcan-migration/tests/fixtures/roundtrip-same-url/`.
- [ ] T102b [P] [US6] Integration test `volcan-migration/tests/integration/ExportImportRoundTripDomainChangeTest.php` — export on `https://origen.example` → import on `https://destino.example`. Asserts serialization-safe URL replacement in `wp_options`, `wp_postmeta`, widgets, and the customizer. Fixture: `volcan-migration/tests/fixtures/roundtrip-domain-change/`.
- [ ] T102c [P] [US6] Integration test `volcan-migration/tests/integration/ExportImportRoundTripSubdirectoryTest.php` — export on `https://example.com/origen` → import on `https://example.com/destino`. Asserts correct rewriting of subdirectory paths in both absolute and relative URLs. Fixture: `volcan-migration/tests/fixtures/roundtrip-subdirectory/`.

### Implementation for User Story 6

- [ ] T103 [P] [US6] Create `volcan-migration/src/Archive/VolcanReader.php` — sequential reader matching `VolcanWriter`; per-entry hash verification; chunked yields
- [ ] T104 [P] [US6] Create `volcan-migration/src/Import/VersionGuard.php` — compares manifest's `wp_version` to `get_bloginfo('version')` per `research.md` R11
- [ ] T105 [US6] Create `volcan-migration/src/Import/SafetyBackup.php` — chunked DB dump to `tmp/<op_id>/safety.sqldump` BEFORE any destructive write
- [ ] T106 [P] [US6] Create `volcan-migration/src/Import/FileRestorer.php` — extracts archive entries via `VolcanReader`, every path passed through `PathGuard`, chunked across ticks
- [ ] T107 [US6] Create `volcan-migration/src/Import/DatabaseRestorer.php` — chunked SQL replay through `$wpdb->query` (DDL first, then INSERTs in batches), serialization-safe
- [ ] T108 [P] [US6] Create `volcan-migration/src/Import/PrefixAdjuster.php` — rewrites table prefixes when origin ≠ destination, including `wp_options.option_name` like `<old_prefix>user_roles`
- [ ] T109 [US6] Create `volcan-migration/src/Import/UrlReplacer.php` — token-stream rewriter walking `s:`/`a:`/`O:` tokens; recomputes byte lengths; configurable target tables (`wp_options`, `wp_postmeta`, `wp_usermeta`, `wp_termmeta`, `wp_posts`)
- [ ] T110 [US6] Create `volcan-migration/src/Import/Importer.php` — orchestrator state-machine (`validate → safety_backup → files → db → url_replace → prefix_adjust → done`)
- [ ] T111 [US6] Create `volcan-migration/src/Ajax/ImportStart.php` — implements `contracts/import.md` `volcanmig_import_start` (drive source: download into `tmp/<op_id>/`, validate header + manifest, run VersionGuard)
- [ ] T112 [US6] Create `volcan-migration/src/Ajax/ImportTick.php` — runs one tick of `Importer`
- [ ] T113 [US6] Create `volcan-migration/src/Ajax/ImportCancel.php` — cancellation at next safe boundary; offers safety restore
- [ ] T114 [US6] Create `volcan-migration/src/Ajax/ImportRestoreSafety.php` — replays `safety.sqldump` via the same tick runner with a smaller sub-machine
- [ ] T115 [P] [US6] Create `volcan-migration/src/Admin/Pages/ImportPage.php` — source picker (Drive / PC), URL-change confirmation modal, progress bar, restore-safety CTA on failure
- [ ] T116 [P] [US6] Create `volcan-migration/assets/js/admin-import.js` — wires ImportPage flows
- [ ] T117 [P] [US6] Add fixtures `volcan-migration/tests/fixtures/serialized/{nested-array.bin,stdclass.bin,custom-class.bin,encoded-urls.bin,url-chain.bin}` for UrlReplacer

**Checkpoint**: US6 acceptance scenarios 1–6 pass.

---

## Phase 9: User Story 7 — Importar un backup desde la PC (Priority: P2)

**Goal**: Admin uploads an archive directly from the browser in chunks, bypassing `upload_max_filesize`, and the import flow auto-starts.

**Independent Test**: Pick a previously generated archive on disk, upload via the Import tab, verify the plugin assembles it and triggers the import flow over it.

### Tests for User Story 7

- [ ] T118 [P] [US7] Integration test `volcan-migration/tests/integration/PcUploadChunkedTest.php` — 5 MB fixture file, multi-chunk upload, simulated mid-flight interruption + resume from last index, finalize sha256 mismatch rejected

### Implementation for User Story 7

- [ ] T119 [P] [US7] Create `volcan-migration/src/Ajax/PcUploadInit.php` — implements `contracts/pc-upload.md` `volcanmig_pc_upload_init`
- [ ] T120 [P] [US7] Create `volcan-migration/src/Ajax/PcUploadChunk.php` — appends to `tmp/<sid>/file.volcan` after per-chunk sha256 check
- [ ] T121 [P] [US7] Create `volcan-migration/src/Ajax/PcUploadFinalize.php` — overall sha256 verify + cheap header validation, returns session id
- [ ] T122 [P] [US7] Create `volcan-migration/assets/js/admin-pc-upload.js` — `Blob.slice` + `fetch` chunked uploader, retry on transient failure, exposes progress events
- [ ] T123 [US7] Extend `volcan-migration/src/Ajax/ImportStart.php` to accept `source='pc'` with `pc_session_id`
- [ ] T124 [P] [US7] Wire `volcanmig_pc_upload_gc` cron handler to drop sessions idle > 2 h

**Checkpoint**: US7 acceptance scenarios 1–4 pass.

---

## Phase 10: User Story 8 — Funcionar en multisite (Priority: P2)

**Goal**: Plugin operates correctly on single-site and multisite, with `manage_network_options` enforced and per-subsite folders/exports/imports.

**Independent Test**: Network-activate the plugin on a multisite, run an export from a subsite as super-admin, verify the archive contains only that subsite's tables and uploads.

### Tests for User Story 8

- [ ] T125 [P] [US8] Unit test `volcan-migration/tests/unit/CapabilityTest.php` — single-site → `manage_options`, multisite root → `manage_network_options`, multisite subsite → `manage_network_options`
- [ ] T126 [P] [US8] Integration test `volcan-migration/tests/integration/MultisiteSubsiteRoundTripTest.php` — export subsite "/blog2/" with prefix `wp_2_`, import into "/blog9/" with prefix `wp_9_`, verify functional

### Implementation for User Story 8

- [ ] T127 [P] [US8] Update `volcan-migration/src/Admin/Menu.php` — register network admin pages alongside per-site pages with the right capability
- [ ] T128 [P] [US8] Update `volcan-migration/src/OAuth/TokenStore.php` — read/write `wp_sitemeta` on multisite (single network-wide connection)
- [ ] T129 [US8] Update `volcan-migration/src/Drive/FolderResolver.php` — per-subsite child folders under one network root folder, naming derived from each subsite's domain/path
- [ ] T130 [US8] Update `volcan-migration/src/Export/DatabaseDumper.php` to dump only `$wpdb->base_prefix . $blog_id . '_*'` tables on multisite subsites
- [ ] T131 [US8] Update `volcan-migration/src/Export/FileCollector.php` to source uploads from `wp-content/uploads/sites/<blog_id>/` on multisite subsites
- [ ] T132 [US8] Update `volcan-migration/src/Import/PrefixAdjuster.php` to handle subsite-prefix rewrites (`wp_2_` → `wp_9_`)

**Checkpoint**: US8 acceptance scenarios 1–4 pass.

---

## Phase 11: User Story 9 — Ver logs de operaciones (Priority: P2)

**Goal**: Admin views per-operation log timelines, downloads logs as txt/ndjson, and sees automatic rotation working.

**Independent Test**: Run an export and an import; open Logs tab; see one row per operation with detail views; download logs; grep the file for "token" / "secret" / "password" → no hits.

### Tests for User Story 9

- [ ] T133 [P] [US9] Unit test `volcan-migration/tests/unit/LogsListTest.php` — pagination, filtering by status/type/operation_id; values pass through Redactor on serialization
- [ ] T134 [P] [US9] Unit test `volcan-migration/tests/unit/RotatorTest.php` — keeps newest 50 per blog; deletes ops older than 90 days; cascades to log rows

### Implementation for User Story 9

- [ ] T135 [P] [US9] Create `volcan-migration/src/Admin/Pages/LogsPage.php` — operations table + per-row drill-down view
- [ ] T136 [P] [US9] Create `volcan-migration/assets/js/admin-logs.js` — pagination, filters, drill-down, "Descargar logs" button
- [ ] T137 [US9] Create `volcan-migration/src/Ajax/LogsList.php` — implements `contracts/logs.md` `volcanmig_logs_list`
- [ ] T138 [US9] Create `volcan-migration/src/Ajax/LogsDownload.php` — streams `txt` or NDJSON
- [ ] T139 [US9] Create `volcan-migration/src/Ajax/LogsPurge.php` — manual one-shot rotation invoking `Rotator`

**Checkpoint**: US9 acceptance scenarios 1–4 pass.

---

## Phase 12: Polish & Cross-Cutting Concerns

**Purpose**: Release-readiness — i18n, docs, compliance, audits.

- [ ] T140 [P] Generate `volcan-migration/languages/volcan-migration.pot` via `tools/build-release.sh`
- [ ] T141 [P] Seed `volcan-migration/languages/volcan-migration-{es_AR,es_ES,pt_BR}.po` with priority strings translated
- [ ] T142 [P] Fill `volcan-migration/readme.txt` (full WP.org content: Description, Installation, FAQ, Privacy, Changelog) and validate against the WP.org Readme Validator
- [ ] T143 [P] Update `volcan-migration/CHANGELOG.md` with the v1.0.0 entry summarizing US1–US9
- [ ] T144 [P] Document the public hook surface from `research.md` R12 in `docs/hooks.md`
- [ ] T145 Run `wp-cli plugin-check` (or the official `wordpress/plugin-check-action`) and confirm zero warnings
- [ ] T146 Coverage gate: enforce `UrlReplacer ≥ 90%` and `Database/Archiver/UrlReplacer/ChunkedUploader ≥ 70%` in `phpunit.xml.dist` and CI job
- [ ] T147 [P] Network-traffic audit: run mitmproxy across the full quickstart and assert zero requests outside `*.googleapis.com`, `*.google.com`, `api.wordpress.org` (SC-006)
- [ ] T148 Run `quickstart.md` end-to-end on a real shared-hosting fixture and a developer docker fixture; record evidence in PR description. **Additionally** for v1.0.0:
    - **SC-002 release gate**: validate manually on at least 3 representative shared-hosting fixtures (cPanel/Hostinger-like, Plesk-like, Kinsta-like — or accessible equivalents). Document each run's outcome in `docs/release-validation-v1.0.0.md`.
    - **SC-009 release gate**: take 5 real errors encountered during release testing and verify the produced log is sufficient to diagnose root cause without server access. Document each in the same file.
    - **§VI.4 manual sweep**: in addition to T014a's CI grep, manually confirm no `error_log`, `var_dump`, `print_r`, `die`, or `dd` calls landed in merged code by spot-checking `volcan-migration/src/` near release time.
- [ ] T149 [P] Verify `defined('ABSPATH') || exit;` is the first non-comment statement of every `volcan-migration/src/**/*.php` (PHPCS sniff)
- [ ] T150 Tag release `v1.0.0` and prepare WP.org SVN sync materials (out of scope for the merge to `main` itself)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: starts immediately.
- **Phase 2 (Foundational)**: starts after Phase 1; **blocks** all user stories.
- **Phase 3 (US1)**: blocks Phase 4 (US2) — credentials must persist before OAuth can read them.
- **Phase 4 (US2)**: blocks Phases 6, 7, 8 (Drive-dependent stories).
- **Phase 5 (US3)**: independent of Phase 4. Blocks Phase 6 (US4 needs an archive to upload).
- **Phase 6 (US4)**: blocks Phase 7 (US5 lists what US4 uploaded — though strictly US5 only needs US2; it can ship before US4 is fully landed and just shows an empty state).
- **Phase 7 (US5)**: blocks Phase 8 (US6 imports from a Drive backup discovered via US5 list).
- **Phase 8 (US6)**: blocks Phase 9 (US7 funnels into the same import flow).
- **Phase 10 (US8 multisite)** and **Phase 11 (US9 logs)**: depend only on Phase 2 + the surfaces they touch (logs reads are foundational; multisite is cross-cutting). Can run in parallel with Phases 5–9 by a different developer.
- **Phase 12 (Polish)**: depends on all stories being functionally complete.

### Within Each User Story

- Tests in the story's "Tests" sub-phase MUST be written and FAIL before the implementation tasks land (TDD per Constitution §VI.6).
- Models / DTOs before services; services before AJAX endpoints; endpoints before page wiring and JS.
- Story is **complete** only when all its acceptance scenarios from `spec.md` pass and CI gates are green.

### Parallel Opportunities

- **Phase 1**: T003 – T014 can run fully in parallel after T001 + T002.
- **Phase 2**: T017 – T044 marked [P] split across files; the OperationRepository (T026) blocks OperationLock (T027) blocks BackgroundLoopback (T034) which blocks AjaxHandler (T035).
- **US1 vs US3**: US3 (export, local-only) can be developed in parallel with US1+US2 (auth/connect) by separate developers, since they touch disjoint code (only `OperationLock` + `BackgroundLoopback` + `Logger` are shared).
- **US8 (multisite)** can land in parallel once US3+US6 baseline is done — it's an adapter layer.
- **US9 (logs)** can be developed in parallel with US3–US7 because the underlying logger is foundational.

---

## Parallel Example: User Story 3 (Export)

```bash
# After T065-T068 unit tests are written and failing,
# the four implementation modules can be built in parallel:
Task: "T069 [P] [US3] Create volcan-migration/src/Archive/VolcanWriter.php"
Task: "T070 [P] [US3] Create volcan-migration/src/Export/DatabaseDumper.php"
Task: "T071 [P] [US3] Create volcan-migration/src/Export/FileCollector.php"
Task: "T072 [P] [US3] Create volcan-migration/src/Export/ManifestBuilder.php"

# Then the orchestrator (T073) integrates them, followed by AJAX endpoints (T074–T076).
```

---

## Implementation Strategy

### MVP First (US1 + US2 + US3 + US4 + US5 + US6)

The constitution says the product's central value is "clone full WP site via Google Drive". The smallest releasable MVP therefore covers:

1. Phase 1 — Setup
2. Phase 2 — Foundational
3. Phase 3 — US1 Configurar
4. Phase 4 — US2 Conectar Drive
5. Phase 5 — US3 Export
6. Phase 6 — US4 Upload to Drive
7. Phase 7 — US5 List backups
8. Phase 8 — US6 Import from Drive
9. Phase 12 — Polish (subset: PHPCS/PHPStan/Plugin Check + readme + .pot)

**STOP and VALIDATE** the quickstart's golden path (US1 → US6) before continuing.

### Incremental Delivery

10. Add Phase 9 — US7 PC upload → release as `1.0.x`.
11. Add Phase 10 — US8 multisite → release as `1.1.0`.
12. Add Phase 11 — US9 logs UI surface → release as `1.1.x` (the underlying logger has been live since Phase 2; this just exposes the UI).

### Parallel Team Strategy

With three developers after Phase 2:

- **Dev A**: US1 → US2 → US5 (auth + Drive surfaces).
- **Dev B**: US3 → US4 (archive + upload pipelines).
- **Dev C**: US6 (import + URL replace), then US9 logs UI.
  Then US7 (PC upload, depends on US6) and US8 (multisite, integrates everything) are picked up by whoever finishes first.

---

## Notes

- [P] = different files, no dependencies on incomplete tasks.
- [Story] tags map every story-phase task back to its user story for traceability.
- Each story's checkpoint must be reachable independently — a half-finished story should not break preceding stories.
- Tests fail before implementation lands (Constitution §VI.6 + §IX TDD-by-default in `superpowers:test-driven-development`).
- Commit per task or per logical group — git extension is wired for optional auto-commit per phase.
- Avoid: vague tasks, same-file conflicts inside a [P] group, cross-story dependencies that compromise independence.
- All AJAX endpoints in this plan are **server-driven** — no public REST API is exposed in v1.0 (per `contracts/README.md`).

---

## Backlog v1.1 (no incluido en v1.0)

Findings explicitly accepted as out-of-scope for the v1.0 release — re-evaluate when v1.1 planning starts.

- **E4**: integration test for OAuth token revoked from the Google Cloud console (next operation must surface a "reconnect" prompt with a clean failure path).
- **E5**: integration test for an import interrupted by plugin deactivation (verify the operation row is detected as stale on reactivation and the user is offered resume / restore-safety).
- **A2**: standardize wording of "mensaje claro" across FRs (cosmetic — current contracts already enforce code-based error keys, so no functional impact).
- **D1**: refactor to deduplicate the cancel-and-cleanup logic across `Export\Exporter`, `Drive\ResumableUploader`, and `Import\Importer` (structural symmetry, not a true duplicate today).
