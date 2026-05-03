# Contract: Export (US3)

Covers FR-010 … FR-015.

The export is a 3-call protocol from the browser:
1. `volcanmig_export_start` returns an `operation_id`.
2. The browser polls `volcanmig_export_tick` every ~2 s; the server processes one chunk per tick and returns progress.
3. `volcanmig_export_cancel` if the user cancels; otherwise `volcanmig_export_tick` returns `done:true` when finished.

All three: capability + nonce required.

## `volcanmig_export_start`

- **Nonce action**: `volcanmig_export_start`

**Request**:
| Field             | Type     | Required | Validation                                                        |
|-------------------|----------|----------|-------------------------------------------------------------------|
| `include_uploads` | bool-ish | yes      | `(bool) absint(...)`                                              |
| `include_themes`  | bool-ish | yes      |                                                                   |
| `include_plugins` | bool-ish | yes      |                                                                   |
| `include_mu`      | bool-ish | yes      |                                                                   |
| `comment`         | string   | no       | `sanitize_text_field`; ≤ 200 chars; persisted to the manifest     |

**Behavior**:
1. Acquire `OperationLock` for this site → on conflict, `lock_busy`.
2. Insert an `operations` row with `type=export`, `status=running`, initial `state_json`.
3. Return `{ ok: true, operation_id }`.

**Response**:
```json
{ "ok": true, "operation_id": 1234 }
```

---

## `volcanmig_export_tick`

- **Nonce action**: `volcanmig_export_tick`

**Request**:
| Field          | Type | Required | Validation                |
|----------------|------|----------|---------------------------|
| `operation_id` | int  | yes      | `absint`; > 0             |

**Behavior**:
1. Load operation row; if `status != running` → `not_found` (or `cancelled`/`failed`/`completed` depending).
2. Heartbeat: update `last_seen_at`.
3. Run one tick of the export state machine (DB tables → wp-content sets → finalize manifest → close archive).
4. Persist `state_json`, `bytes_done`, `progress_pct`.
5. Return current progress.

**Response (running)**:
```json
{
  "ok": true,
  "status": "running",
  "step": "files",
  "step_label": "Empaquetando uploads",
  "progress_pct": 42,
  "bytes_done": 2147483648,
  "bytes_total": 5103222784
}
```

**Response (done)**:
```json
{
  "ok": true,
  "status": "completed",
  "progress_pct": 100,
  "archive_path": "/wp-content/uploads/volcan-migration/exports/site-2026-05-03-1130.volcan",
  "size_bytes": 5103222784,
  "sha256": "<hex>"
}
```

**Response (failure)**:
```json
{ "ok": false, "code": "internal_error", "message": "..." }
```

---

## `volcanmig_export_cancel`

- **Nonce action**: `volcanmig_export_cancel`

**Request**: `operation_id`.

**Behavior**:
1. Mark `status='cancelled'` so the next tick exits early.
2. Schedule a janitor that removes `tmp/<op_id>/` directory.
3. Release the lock.

**Response**: `{ "ok": true }`.
