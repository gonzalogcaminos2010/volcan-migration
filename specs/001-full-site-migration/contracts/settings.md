# Contract: Settings (US1)

Covers FR-001, FR-002, FR-007.

## `volcanmig_save_credentials`

Save Google Cloud OAuth credentials.

- **Method**: `POST`
- **Capability**: `manage_options` / `manage_network_options`
- **Nonce action**: `volcanmig_save_credentials`

**Request**:
| Field           | Type   | Required | Validation                                                       |
|-----------------|--------|----------|------------------------------------------------------------------|
| `client_id`     | string | yes      | `sanitize_text_field`; matches `^[A-Za-z0-9._-]+\.apps\.googleusercontent\.com$` |
| `client_secret` | string | yes      | `sanitize_text_field`; non-empty; ≤ 256 chars                    |
| `nonce`         | string | yes      |                                                                  |

**Response (success)**:
```json
{ "ok": true, "credentials_present": true }
```

**Response (error)**: `invalid_input` if validation fails.

**Side effects**: Stores credentials inside the encrypted `volcanmig_oauth_tokens` blob (without tokens). If a previous Drive connection exists, it is **invalidated** and the user is told to reconnect.

---

## `volcanmig_get_status`

Read connection status, account, quota.

- **Method**: `GET`
- **Capability**: `manage_options` / `manage_network_options`
- **Nonce action**: `volcanmig_get_status`

**Response (connected)**:
```json
{
  "ok": true,
  "credentials_present": true,
  "connected": true,
  "account_email": "user@example.com",
  "drive_quota": { "used": 12345678901, "limit": 16106127360 },
  "drive_folder_name": "Volcán Migration / example.com"
}
```

**Response (no credentials)**:
```json
{ "ok": true, "credentials_present": false, "connected": false }
```

**Response (credentials only)**:
```json
{ "ok": true, "credentials_present": true, "connected": false }
```

Drive quota fetch failures degrade to `drive_quota: null` — the UI still renders.

---

## `volcanmig_clear_credentials`

Wipe credentials (only allowed when **not** connected; if connected, the UI must call disconnect first).

- **Method**: `POST`
- **Nonce action**: `volcanmig_clear_credentials`
- **Response**: `{ "ok": true }` on success; `{ "ok": false, "code": "still_connected" }` if a connection exists.
