# Contract: Backups in Drive (US5)

Covers FR-030 … FR-032.

## `volcanmig_backups_list`

- **Method**: `GET`
- **Nonce action**: `volcanmig_backups_list`

**Request**:
| Field        | Type   | Required | Notes                                  |
|--------------|--------|----------|----------------------------------------|
| `page_token` | string | no       | Opaque continuation from a prior call  |

**Behavior**:
1. Require Drive connection.
2. List the per-site folder (Drive `files.list`, see `data-model.md` §7), `pageSize=100`.
3. Normalize entries.

**Response**:
```json
{
  "ok": true,
  "items": [
    {
      "drive_file_id": "1AbC...",
      "name": "site-2026-05-03-1130.volcan",
      "size_bytes": 5103222784,
      "modified_at": "2026-05-03T11:30:00Z",
      "wp_version": "6.5.2",
      "site_key_match": true
    }
  ],
  "next_page_token": null
}
```

`site_key_match` is `false` when `appProperties.volcanmig_site_key` doesn't match the current site (eg. cross-site restore). The UI shows a warning badge.

Empty folder → `items: []`. The UI then renders the "No hay backups todavía" empty state.

---

## `volcanmig_backups_delete`

- **Nonce action**: `volcanmig_backups_delete`

**Request**: `drive_file_id`.

**Behavior**:
1. Verify the file lives inside the per-site folder (so we never delete random Drive files).
2. `files.delete` (skipTrash) — Drive moves to trash; we explicitly skip trash to honor the "free up space" intent.
3. Log the deletion (with the file name, NOT the file ID — IDs leaking is low risk but unnecessary).

**Response**: `{ "ok": true }`.

---

## `volcanmig_backups_download`

- **Nonce action**: `volcanmig_backups_download`

**Request**: `drive_file_id`.

**Behavior**:
- Streams the file inline from Drive to the browser via PHP (`fpassthru` over the Drive download URL).
- `Content-Disposition: attachment; filename="<sanitized name>"`.
- `Content-Length` set when Drive returns it.
- On network error mid-stream: 502.

This endpoint is special — it returns binary, not JSON.

**Alternative**: when the file is large enough that streaming through PHP is risky (>2 GB), the server instead returns a short-lived signed `webContentLink` from Drive and lets the browser fetch directly:
```json
{ "ok": true, "redirect": "https://drive.google.com/uc?id=<id>&export=download" }
```
The UI follows this link in a new tab. The "stream-through-PHP" mode is preferred when feasible because it keeps the user inside `wp-admin`.
