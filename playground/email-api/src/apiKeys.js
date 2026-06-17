import { createHash } from "node:crypto";
import { ApiError, validationError, notFound } from "./errors.js";
import { newId, newApiToken } from "./ids.js";

const PERMISSIONS = new Set(["full_access", "sending_access"]);

// We never store the raw token, only its SHA-256. Lookups hash the incoming
// token and match by hash, so a DB leak can't be replayed against the API.
const hashToken = (token) => createHash("sha256").update(token).digest("hex");

const display = (token) => `${token.slice(0, 6)}...${token.slice(-4)}`;

// Mint a key. The raw token is returned exactly once here — it can never be
// recovered afterwards, same as Resend's dashboard.
export function createApiKey(db, { name, permission = "full_access" } = {}) {
  if (!name || typeof name !== "string") {
    throw validationError("`name` is required to create an API key.");
  }
  if (!PERMISSIONS.has(permission)) {
    throw validationError(`\`permission\` must be one of: ${[...PERMISSIONS].join(", ")}.`);
  }

  const token = newApiToken();
  const id = newId();
  const createdAt = new Date().toISOString();
  db.prepare(
    `INSERT INTO api_keys (id, name, token_hash, prefix, permission, created_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  ).run(id, name, hashToken(token), display(token), permission, createdAt);

  return { object: "api_key", id, name, permission, token, created_at: createdAt };
}

// Resolve an `Authorization: Bearer <token>` header to its API key row, or
// throw the appropriate 401. Bumps last_used_at as a side effect.
export function authenticate(db, authorizationHeader) {
  if (!authorizationHeader) {
    throw new ApiError(401, "missing_api_key", "Missing API key in the Authorization header.");
  }
  const match = /^Bearer\s+(\S+)$/i.exec(authorizationHeader.trim());
  if (!match) {
    throw new ApiError(401, "invalid_api_key", "Malformed Authorization header. Expected `Bearer re_...`.");
  }

  const row = db.prepare(`SELECT * FROM api_keys WHERE token_hash = ?`).get(hashToken(match[1]));
  if (!row) {
    throw new ApiError(401, "invalid_api_key", "API key is invalid.");
  }

  db.prepare(`UPDATE api_keys SET last_used_at = ? WHERE id = ?`).run(new Date().toISOString(), row.id);
  return row;
}

export function listApiKeys(db) {
  const rows = db
    .prepare(`SELECT id, name, permission, created_at FROM api_keys ORDER BY created_at DESC, rowid DESC`)
    .all();
  return rows.map((r) => ({ object: "api_key", ...r }));
}

export function revokeApiKey(db, id) {
  const { changes } = db.prepare(`DELETE FROM api_keys WHERE id = ?`).run(id);
  if (changes === 0) {
    throw notFound("API key not found.");
  }
  return { object: "api_key", id, deleted: true };
}
