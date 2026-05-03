# Contract: PC Upload (US7)

Covers FR-046, FR-047.

3-call protocol: init → chunk (× N) → finalize. The finalize call returns a `pc_session_id` that `volcanmig_import_start` accepts as `source=pc`.

## `volcanmig_pc_upload_init`

- **Method**: `POST`
- **Nonce action**: `volcanmig_pc_upload_init`

**Request**:
| Field           | Type | Required | Notes                                                                |
|-----------------|------|----------|----------------------------------------------------------------------|
| `expected_size` | int  | yes      | Total bytes; rejected if > `volcanmig_pc_upload_max_bytes` filter    |
| `expected_sha256` | str | yes      | Hex digest the client will verify against on finalize                |
| `chunk_size`    | int  | yes      | Must be a multiple of 256 KiB and ≤ 8 MiB                            |
| `total_chunks`  | int  | yes      | `ceil(expected_size / chunk_size)`                                   |

**Behavior**:
1. Acquire `OperationLock`.
2. Allocate a `pc_session_id` (32 hex chars) and a `tmp/<sid>/` directory.
3. Persist `volcanmig_pc_upload_<sid>` option with the metadata above + `created_at` + `last_seen_at`.

**Response**:
```json
{ "ok": true, "session_id": "f2c3...", "next_chunk_index": 0 }
```

---

## `volcanmig_pc_upload_chunk`

- **Method**: `POST` (multipart/form-data)
- **Nonce action**: `volcanmig_pc_upload_chunk`

**Request**:
| Field          | Where    | Required | Notes                                          |
|----------------|----------|----------|------------------------------------------------|
| `session_id`   | form     | yes      |                                                |
| `chunk_index`  | form     | yes      | 0-based                                        |
| `chunk`        | file     | yes      | The binary chunk                               |
| `chunk_sha256` | form     | yes      | Hex digest of the chunk for integrity         |

**Behavior**:
1. Validate session exists and `chunk_index` is the **next expected** index. If out of order → `invalid_input` (the client may rewind).
2. Hash the uploaded chunk; mismatch → `invalid_input` and discard.
3. Append to `tmp/<sid>/file.volcan`.
4. Update session: `next_chunk_index++`, `received_bytes`, `last_seen_at`.

**Response**:
```json
{ "ok": true, "next_chunk_index": 21, "received_bytes": 167772160 }
```

---

## `volcanmig_pc_upload_finalize`

- **Method**: `POST`
- **Nonce action**: `volcanmig_pc_upload_finalize`

**Request**: `session_id`.

**Behavior**:
1. Verify all chunks received.
2. Recompute SHA-256 over the assembled file. Mismatch → `invalid_input`, delete session.
3. Validate the archive header + manifest cheaply (just enough to know it's a `VOLCAN1\n` file). Invalid → `invalid_input` and delete.
4. Mark the session ready and return its id; the UI then calls `volcanmig_import_start` with `source='pc'`.

**Response**:
```json
{ "ok": true, "session_id": "f2c3...", "size_bytes": 5103222784 }
```
