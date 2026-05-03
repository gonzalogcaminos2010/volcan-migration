# Contract: OAuth (US2)

Covers FR-003, FR-005, FR-006.

The OAuth callback is **not** an AJAX endpoint; it is a regular admin-init handler so Google can redirect to a normal URL. The other two are AJAX.

## `volcanmig_oauth_start`

Begin the OAuth consent flow.

- **Method**: `POST`
- **Capability**: `manage_options` / `manage_network_options`
- **Nonce action**: `volcanmig_oauth_start`

**Request**: just `nonce`.

**Response**:
```json
{
  "ok": true,
  "authorize_url": "https://accounts.google.com/o/oauth2/v2/auth?...&state=<random>&redirect_uri=<plugin_callback>"
}
```

**Server side**:
- `state` is a single-use CSRF token persisted in a 10-minute transient `volcanmig_oauth_state_<hash>` keyed to the current user.
- `redirect_uri` is `admin_url('admin.php?page=volcanmig-settings&volcanmig_oauth_callback=1')` — single-site — or its multisite equivalent. The user must register this URL in their Google Cloud OAuth client.
- `scope` is hardcoded to `https://www.googleapis.com/auth/drive.file`.
- `access_type=offline&prompt=consent` to guarantee a refresh token on first connect.

The browser then redirects the user (top window navigation) to `authorize_url`.

---

## OAuth callback (`?volcanmig_oauth_callback=1`)

- **Method**: `GET` (Google's redirect)
- **Capability**: `manage_options` / `manage_network_options` (the user must already be logged in as admin on the same browser).
- **CSRF**: validated against the `state` transient.

**Query params**: `code`, `state`, optional `error`.

**Behavior**:
1. Verify state. If invalid → render the settings page with a "verification failed" notice.
2. Exchange `code` for tokens via the user's OAuth client.
3. Encrypt and persist the full token blob.
4. Resolve / create the per-site Drive folder; cache its ID.
5. Redirect back to the settings page with `?volcanmig_connected=1`.

On error path (`?error=access_denied` etc.), render a notice and stay disconnected.

---

## `volcanmig_disconnect`

- **Method**: `POST`
- **Capability**: `manage_options` / `manage_network_options`
- **Nonce action**: `volcanmig_disconnect`

**Behavior**:
1. Best-effort `POST https://oauth2.googleapis.com/revoke?token=<refresh_token>`. Failure is logged but does not block local cleanup.
2. Delete the encrypted token blob (preserve `client_id`/`client_secret` so the user can reconnect without re-entering them).
3. Clear cached `drive_folder_id`.

**Response**: `{ "ok": true }`.
