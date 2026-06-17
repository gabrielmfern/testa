# email-api

A small but real-world-shaped HTTP API for sending email, modeled on Resend's
developer experience. SQLite for storage (`node:sqlite`, no native deps),
nodemailer for delivery, Bearer API keys for auth. It exists to give the `testa`
runner a realistic, non-trivial test suite to chew on.

## Layout

| File | Responsibility |
| --- | --- |
| `src/db.js` | Opens the SQLite database and applies the schema (api_keys, emails, idempotency_keys). |
| `src/apiKeys.js` | Mints, authenticates, lists, and revokes API keys. Stores only a SHA-256 of each token. |
| `src/emails.js` | Validates payloads, persists the email, dispatches via a nodemailer transport, supports idempotency. |
| `src/mailer.js` | nodemailer transport factory (JSON transport by default, SMTP when configured). |
| `src/server.js` | `node:http` server: routing, auth, permission checks, Resend-style JSON errors. |
| `src/client.js` | `EmailClient` — a tiny SDK shaped like the `resend` package; methods resolve to `{ data, error }`. |
| `index.js` | Runnable entry: seeds a key on first boot and starts the server. |

## Run it

```sh
# from playground/
pnpm email-api
# -> prints a seeded re_... key once, then listens on :3000
# Set SMTP_URL=smtp://user:pass@host:587 to send for real; otherwise mail is
# serialized via nodemailer's JSON transport. DATABASE_PATH defaults to ./email-api.db.
```

```sh
curl -X POST http://localhost:3000/emails \
  -H "Authorization: Bearer re_..." -H "Content-Type: application/json" \
  -d '{"from":"you@yours.com","to":"them@theirs.com","subject":"hi","text":"hello"}'
```

## Endpoints

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| `POST` | `/emails` | any key | Honors the `Idempotency-Key` header. Returns `{ id }`. |
| `GET` | `/emails/:id` | any key | Scoped to the calling key. |
| `POST` | `/api-keys` | full_access | `{ name, permission }`; returns the raw token once. |
| `GET` | `/api-keys` | full_access | Secrets omitted. |
| `DELETE` | `/api-keys/:id` | full_access | |

`sending_access` keys may send and read emails but cannot manage keys.
