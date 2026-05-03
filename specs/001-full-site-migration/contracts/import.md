# Contract: Import (US6)

Covers FR-040 … FR-045.

Like export, import is start / tick / cancel + a special restore endpoint for the safety backup.

## `volcanmig_import_start`

- **Nonce action**: `volcanmig_import_start`

**Request** (one of these source variants):
| Field              | Type   | Required | Notes                                                   |
|--------------------|--------|----------|---------------------------------------------------------|
| `source`           | string | yes      | `'drive'` \| `'pc'`                                     |
| `drive_file_id`    | string | when source=drive | The selected Drive file's ID                   |
| `pc_session_id`    | string | when source=pc    | The PC upload session id (US7)                 |
| `confirm_url_change` | bool | yes      | Must be `true` if origin URL ≠ destination URL          |
| `dry_run`          | bool   | no       | If `true`, validate but do not modify anything           |

**Behavior**:
1. Capability + nonce + `OperationLock`.
2. If `source='drive'`: download the archive into `tmp/<op_id>/` (its own ticked sub-state — see below).
3. If `source='pc'`: rename the assembled `tmp/<sid>/file.volcan` into `tmp/<op_id>/`.
4. Validate the archive header + manifest. On invalid format → `invalid_input` and discard.
5. Run `VersionGuard`. On major-WP mismatch → `version_mismatch`.
6. Insert `operations` row, `type=import`, `status=running`.

**Response**:
```json
{ "ok": true, "operation_id": 1236, "needs_url_change_confirmation": true,
  "manifest": { "site_url": "https://old.com", "wp_version": "6.5.2", "db_prefix": "wp_" } }
```

If `needs_url_change_confirmation` is true and `confirm_url_change` was not, the server returns `{ ok: false, code: 'confirm_required', manifest: ... }` — the UI then prompts the user.

---

## `volcanmig_import_tick`

- **Nonce action**: `volcanmig_import_tick`

**Behavior** — runs the state machine (`validate → safety_backup → files → db → url_replace → prefix_adjust → done`).

Each tick processes one chunk:
- `safety_backup`: DB dump of the destination's tables in chunks; persisted under `tmp/<op_id>/safety.sqldump`.
- `files`: extract the next archive entry (or chunk of an entry) into the destination, validating paths via `PathGuard`.
- `db`: replay the next batch of SQL statements (chunked by row count, not by line).
- `url_replace`: walk one batch of rows of `wp_options`, `wp_postmeta`, `wp_usermeta`, `wp_termmeta`, `wp_posts` (and any custom-prefix equivalents), apply serialization-safe replacement.
- `prefix_adjust`: rewrite table prefixes if origin ≠ dest.

**Response (running)**:
```json
{
  "ok": true,
  "status": "running",
  "step": "url_replace",
  "step_label": "Reescribiendo URLs",
  "progress_pct": 73,
  "bytes_done": 3744000000,
  "bytes_total": 5103222784
}
```

**Response (done)**:
```json
{
  "ok": true,
  "status": "completed",
  "safety_backup_path": "/wp-content/uploads/volcan-migration/tmp/1236/safety.sqldump"
}
```

**Response (failed)**:
```json
{
  "ok": false,
  "code": "internal_error",
  "message": "...",
  "operation_id": 1236,
  "safety_backup_available": true
}
```

---

## `volcanmig_import_cancel`

- **Nonce action**: `volcanmig_import_cancel`

**Behavior**:
- Stop at the next safe boundary (between sub-steps).
- Offer the same restore-safety flow as on failure (see below).

---

## `volcanmig_import_restore_safety`

- **Nonce action**: `volcanmig_import_restore_safety`

**Request**: `operation_id`.

**Behavior**:
1. Load the operation; require it to be `failed` or `cancelled` AND have a `safety_backup_path`.
2. Acquire the OperationLock (this also serializes against any new import attempt).
3. Replay the safety SQL dump through `wpdb` in chunks, with progress.
4. Mark the original failed operation `result_code='restored'`.

**Response (done)**:
```json
{ "ok": true, "status": "completed" }
```

This restoration is itself ticked — the actual implementation reuses the same tick runner but with a smaller sub-state machine.
