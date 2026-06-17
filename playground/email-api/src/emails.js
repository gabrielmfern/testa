import { validationError, notFound } from "./errors.js";
import { newId } from "./ids.js";

const MAX_RECIPIENTS = 50;

// Accepts a bare address or a "Display Name <addr@host>" form; validates the
// address part loosely (real deliverability is the SMTP server's problem).
function assertAddress(value, field) {
  if (typeof value !== "string") throw validationError(`\`${field}\` must be a string.`);
  const addr = value.includes("<") ? value.replace(/^.*<([^>]+)>.*$/, "$1") : value;
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(addr.trim())) {
    throw validationError(`\`${field}\` is not a valid email address: ${value}`);
  }
}

function toRecipientList(value, field) {
  const list = Array.isArray(value) ? value : [value];
  if (list.length === 0) throw validationError(`\`${field}\` must have at least one recipient.`);
  if (list.length > MAX_RECIPIENTS) {
    throw validationError(`\`${field}\` accepts at most ${MAX_RECIPIENTS} recipients.`);
  }
  for (const addr of list) assertAddress(addr, field);
  return list;
}

function validate(payload) {
  if (!payload || typeof payload !== "object") throw validationError("Request body must be a JSON object.");
  assertAddress(payload.from, "from");
  const to = toRecipientList(payload.to, "to");
  if (!payload.subject || typeof payload.subject !== "string") {
    throw validationError("`subject` is required.");
  }
  if (payload.html == null && payload.text == null) {
    throw validationError("Provide at least one of `html` or `text`.");
  }
  return {
    from: payload.from,
    to,
    cc: payload.cc == null ? null : toRecipientList(payload.cc, "cc"),
    bcc: payload.bcc == null ? null : toRecipientList(payload.bcc, "bcc"),
    reply_to: payload.reply_to == null ? null : payload.reply_to,
    subject: payload.subject,
    html: payload.html ?? null,
    text: payload.text ?? null,
  };
}

const json = (value) => (value == null ? null : JSON.stringify(value));
const parse = (value) => (value == null ? null : JSON.parse(value));

function format(row) {
  return {
    object: "email",
    id: row.id,
    from: row.from_addr,
    to: parse(row.to_addrs),
    cc: parse(row.cc),
    bcc: parse(row.bcc),
    reply_to: row.reply_to,
    subject: row.subject,
    html: row.html,
    text: row.text,
    last_event: row.status,
    created_at: row.created_at,
  };
}

export function getEmail(db, apiKeyId, id) {
  const row = db.prepare(`SELECT * FROM emails WHERE id = ? AND api_key_id = ?`).get(id, apiKeyId);
  if (!row) throw notFound("Email not found.");
  return format(row);
}

// Validate, persist, then hand off to nodemailer. The row is written before the
// send so a crashed dispatch still leaves a `queued` record to reconcile.
export async function sendEmail(db, transport, apiKeyId, payload, { idempotencyKey } = {}) {
  const input = validate(payload);

  if (idempotencyKey) {
    const seen = db
      .prepare(`SELECT email_id FROM idempotency_keys WHERE key = ? AND api_key_id = ?`)
      .get(idempotencyKey, apiKeyId);
    if (seen) return getEmail(db, apiKeyId, seen.email_id);
  }

  const id = newId();
  const createdAt = new Date().toISOString();
  db.prepare(
    `INSERT INTO emails
       (id, api_key_id, from_addr, to_addrs, cc, bcc, reply_to, subject, html, text, status, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'queued', ?)`,
  ).run(
    id,
    apiKeyId,
    input.from,
    json(input.to),
    json(input.cc),
    json(input.bcc),
    input.reply_to,
    input.subject,
    input.html,
    input.text,
    createdAt,
  );

  let status = "sent";
  let providerMessageId = null;
  let errorText = null;
  try {
    const info = await transport.sendMail({
      from: input.from,
      to: input.to,
      cc: input.cc ?? undefined,
      bcc: input.bcc ?? undefined,
      replyTo: input.reply_to ?? undefined,
      subject: input.subject,
      html: input.html ?? undefined,
      text: input.text ?? undefined,
    });
    providerMessageId = info?.messageId ?? null;
  } catch (err) {
    status = "failed";
    errorText = err?.message ?? String(err);
  }

  db.prepare(`UPDATE emails SET status = ?, provider_message_id = ?, error = ? WHERE id = ?`).run(
    status,
    providerMessageId,
    errorText,
    id,
  );

  if (idempotencyKey) {
    db.prepare(
      `INSERT INTO idempotency_keys (key, api_key_id, email_id, created_at) VALUES (?, ?, ?, ?)`,
    ).run(idempotencyKey, apiKeyId, id, createdAt);
  }

  return getEmail(db, apiKeyId, id);
}
