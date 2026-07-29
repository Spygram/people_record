# API Reference

The backend is an Express 5 service exposing a small JSON API over a single PostgreSQL table.

**Base URLs**

| Environment | URL |
| --- | --- |
| Production | `https://api.sujandongol.com.np` |
| Local | `http://localhost:3000` |

No authentication is required. All request and response bodies are `application/json`.

---

## Data model

```sql
CREATE TABLE IF NOT EXISTS person (
  serial_number SERIAL PRIMARY KEY,
  name TEXT,
  age  INT
);
```

Created automatically by the application at startup.

| Field | Type | Notes |
| --- | --- | --- |
| `serial_number` | `integer` | Auto-incrementing primary key |
| `name` | `string` | Person's full name |
| `age` | `integer` | Person's age |

---

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/people` | List all records |
| `POST` | `/submit` | Create a record |
| `POST` | `/delete` | Delete a record by ID |

---

### `GET /people`

Returns every record, ordered by `serial_number` ascending.

**Response `200 OK`**

```json
[
  { "serial_number": 1, "name": "Sujan Dongol", "age": 25 },
  { "serial_number": 2, "name": "Anita Shrestha", "age": 31 }
]
```

An empty table returns `[]`.

**Response `500 Internal Server Error`** — plain text: `Error fetching people`

```bash
curl https://api.sujandongol.com.np/people
```

---

### `POST /submit`

Inserts a new person.

**Request body**

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `name` | string | yes | Full name |
| `age` | integer | yes | Age in years |

```json
{ "name": "Sujan Dongol", "age": 25 }
```

**Response `200 OK`**

```json
{ "success": true }
```

**Response `500 Internal Server Error`**

```json
{ "success": false }
```

```bash
curl -X POST https://api.sujandongol.com.np/submit \
  -H "Content-Type: application/json" \
  -d '{"name":"Sujan Dongol","age":25}'
```

The endpoint also accepts `application/x-www-form-urlencoded`, since `express.urlencoded({ extended: true })` is mounted alongside the JSON parser.

The generated `serial_number` is not returned; the frontend refetches `/people` after a successful submit.

---

### `POST /delete`

Deletes the record with the given primary key. Uses `POST` rather than `DELETE` so the browser client can send a JSON body without additional preflight handling.

**Request body**

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `id` | integer | yes | The `serial_number` to delete |

```json
{ "id": 1 }
```

**Response `200 OK`**

```json
{ "success": true }
```

Deleting a non-existent ID is a no-op and still returns `success: true` — the operation is idempotent.

**Response `500 Internal Server Error`**

```json
{ "success": false }
```

```bash
curl -X POST https://api.sujandongol.com.np/delete \
  -H "Content-Type: application/json" \
  -d '{"id":1}'
```

---

## CORS

The API is consumed from a different origin than it is served from, so CORS is enabled globally:

| Setting | Value |
| --- | --- |
| `origin` | `*` |
| `methods` | `GET`, `POST`, `DELETE`, `OPTIONS` |
| `allowedHeaders` | `Content-Type` |

Browsers issue a preflight `OPTIONS` request before any `POST` carrying a JSON body; this is handled automatically by the `cors` middleware.

---

## Static file serving

The Express app also mounts `express.static` on `../public`, so a single backend container can serve the UI directly when the frontend is not deployed separately. In the Kubernetes and Compose topologies the frontend is its own `nginx:alpine` container, and this mount goes unused.

---

## Errors

| Status | Meaning | Body |
| --- | --- | --- |
| `200` | Success | JSON payload |
| `404` | No matching route | Express default HTML |
| `500` | Database or server error | `{"success": false}` or plain text |

Errors are logged in full to `stdout` (`console.error`) and surface via `kubectl logs` or `docker compose logs`. Client responses are intentionally terse and never leak SQL or connection details.

---

## Startup behaviour

Before binding the HTTP listener, the process attempts `CREATE TABLE IF NOT EXISTS` against the database — **up to 10 attempts, 3 seconds apart**. Success logs:

```
✅ Database initialized (person table ready)
🚀 Server running at 3000
```

If every attempt fails the process logs `❌ Could not connect to database after retries` and exits with code `1`, letting Kubernetes restart the pod or Docker's `restart: always` retry the container. No requests are ever served against an uninitialised schema.
