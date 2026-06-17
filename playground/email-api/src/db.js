import { DatabaseSync } from "node:sqlite";

const SCHEMA = `
CREATE TABLE IF NOT EXISTS api_keys (
  id           TEXT PRIMARY KEY,
  name         TEXT NOT NULL,
  token_hash   TEXT NOT NULL UNIQUE,
  prefix       TEXT NOT NULL,
  permission   TEXT NOT NULL DEFAULT 'full_access',
  created_at   TEXT NOT NULL,
  last_used_at TEXT
);

CREATE TABLE IF NOT EXISTS emails (
  id                  TEXT PRIMARY KEY,
  api_key_id          TEXT NOT NULL,
  from_addr           TEXT NOT NULL,
  to_addrs            TEXT NOT NULL,
  cc                  TEXT,
  bcc                 TEXT,
  reply_to            TEXT,
  subject             TEXT NOT NULL,
  html                TEXT,
  text                TEXT,
  status              TEXT NOT NULL,
  provider_message_id TEXT,
  error               TEXT,
  created_at          TEXT NOT NULL,
  FOREIGN KEY (api_key_id) REFERENCES api_keys (id)
);

CREATE INDEX IF NOT EXISTS emails_by_key ON emails (api_key_id);

-- Idempotency-Key support: a (key, api_key) pair maps to exactly one email so
-- retried POST /emails requests return the original result instead of resending.
CREATE TABLE IF NOT EXISTS idempotency_keys (
  key        TEXT NOT NULL,
  api_key_id TEXT NOT NULL,
  email_id   TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (key, api_key_id)
);
`;

export function openDatabase(path = ":memory:") {
  const db = new DatabaseSync(path);
  db.exec("PRAGMA foreign_keys = ON;");
  db.exec(SCHEMA);
  return db;
}
