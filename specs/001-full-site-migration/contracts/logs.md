# Contract: Logs (US9)

Covers FR-060 … FR-063.

## `volcanmig_logs_list`

- **Method**: `GET`
- **Nonce action**: `volcanmig_logs_list`

**Request**:
| Field         | Type | Required | Notes                                                |
|---------------|------|----------|------------------------------------------------------|
| `page`        | int  | no       | 1-based; default 1                                   |
| `page_size`   | int  | no       | default 25; capped at 100                            |
| `operation_id`| int  | no       | When set, returns log entries for a single operation |
| `status`      | str  | no       | Filter operations by status                          |
| `type`        | str  | no       | Filter operations by type                            |

**Response (operation list)**:
```json
{
  "ok": true,
  "page": 1,
  "page_size": 25,
  "total": 142,
  "items": [
    {
      "id": 1234,
      "type": "export",
      "status": "completed",
      "started_at": "2026-05-03T11:00:00Z",
      "finished_at": "2026-05-03T11:25:00Z",
      "progress_pct": 100,
      "bytes_total": 5103222784,
      "result_code": "ok"
    }
  ]
}
```

**Response (single-operation entries)** when `operation_id` is set:
```json
{
  "ok": true,
  "operation_id": 1234,
  "items": [
    { "ts": "2026-05-03T11:00:00Z", "level": "info", "message": "Export started",
      "context": { "include": { "uploads": true, "themes": true, "plugins": true, "mu-plugins": true } } },
    { "ts": "2026-05-03T11:00:01Z", "level": "info", "message": "Dumping wp_options",
      "context": { "rows": 1234 } }
  ]
}
```

All values are passed through `Log\Redactor` before serialization (defense in depth even though they were already redacted on write).

---

## `volcanmig_logs_download`

- **Method**: `GET`
- **Nonce action**: `volcanmig_logs_download`

**Request**:
| Field         | Type | Required | Notes                                       |
|---------------|------|----------|---------------------------------------------|
| `operation_id`| int  | no       | When set, only that operation; else all     |
| `format`      | str  | no       | `txt` (default) or `json`                   |

**Behavior**:
- Streams the logs in chronological order with `Content-Disposition: attachment`.
- For `txt`: `[ISO timestamp] LEVEL operation=<id> type=<t> message — context`.
- For `json`: NDJSON, one entry per line.

**Returns binary** (not JSON). On failure: standard JSON error.

---

## `volcanmig_logs_purge`

- **Method**: `POST`
- **Capability**: `manage_options` / `manage_network_options`
- **Nonce action**: `volcanmig_logs_purge`

Manual one-shot rotation (otherwise WP-Cron handles it).

**Response**:
```json
{ "ok": true, "purged_operations": 12, "purged_log_rows": 3490 }
```
