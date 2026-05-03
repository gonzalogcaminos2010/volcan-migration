# Contract: Upload to Drive (US4)

Covers FR-020 … FR-024.

Same 3-call shape as export.

## `volcanmig_upload_start`

- **Nonce action**: `volcanmig_upload_start`

**Request**:
| Field          | Type | Required | Validation                                              |
|----------------|------|----------|---------------------------------------------------------|
| `archive_path` | str  | yes      | Server-side: must resolve inside `tmp/` or `exports/`   |
|                |      |          | Server-side: must end with `.volcan`                    |

**Behavior**:
1. Capability + nonce + `OperationLock`.
2. Verify `not_connected` if Drive is not bound.
3. Pre-check Drive quota: free bytes ≥ archive size + 5 % overhead. Else `quota_exceeded` with `{ free_bytes, needed_bytes }`.
4. Resolve / create the per-site folder.
5. Open a Drive **resumable session**, store the session URL (encrypted) on the operation row.
6. Insert `operations` row `type=upload`, `status=running`.

**Response**:
```json
{ "ok": true, "operation_id": 1235 }
```

---

## `volcanmig_upload_tick`

- **Nonce action**: `volcanmig_upload_tick`

**Behavior**:
- Push one 8 MiB chunk to Drive via `Content-Range`.
- On 308: store the new offset reported by Drive; update `bytes_done`.
- On 5xx / 408 / 429: exponential backoff (1, 2, 4, 8, 16 s), then surface a transient `network_error` so the UI shows "retrying"; the next tick retries.
- On 401: refresh the access token, retry the same chunk.
- On 200/201: completion — store `drive_file_id`, set Drive `appProperties` (see `data-model.md` §7), close.

**Response (running)**:
```json
{
  "ok": true,
  "status": "running",
  "progress_pct": 64,
  "bytes_done": 3221225472,
  "bytes_total": 5103222784
}
```

**Response (done)**:
```json
{
  "ok": true,
  "status": "completed",
  "drive_file_id": "1AbC...",
  "drive_file_name": "site-2026-05-03-1130.volcan"
}
```

---

## `volcanmig_upload_cancel`

- **Nonce action**: `volcanmig_upload_cancel`

**Behavior**:
1. Mark cancelled.
2. `DELETE` the resumable session URL on Drive (best-effort; failure is logged).
3. Release lock.

**Response**: `{ "ok": true }`.
