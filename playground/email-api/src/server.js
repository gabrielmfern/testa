import { createServer as createHttpServer } from "node:http";
import { ApiError, notFound } from "./errors.js";
import { authenticate, createApiKey, listApiKeys, revokeApiKey } from "./apiKeys.js";
import { sendEmail, getEmail } from "./emails.js";

function send(res, status, body) {
  const payload = body == null ? "" : JSON.stringify(body);
  res.writeHead(status, { "content-type": "application/json" });
  res.end(payload);
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("error", reject);
    req.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf8");
      if (raw.length === 0) return resolve({});
      try {
        resolve(JSON.parse(raw));
      } catch {
        reject(new ApiError(422, "validation_error", "Request body is not valid JSON."));
      }
    });
  });
}

const requireFullAccess = (key) => {
  if (key.permission !== "full_access") {
    throw new ApiError(401, "restricted_api_key", "This endpoint requires a full-access API key.");
  }
};

// Routes are matched here so handlers stay free of parsing concerns. Every
// route authenticates first; key management additionally requires full access.
async function route(db, transport, req, res) {
  const url = new URL(req.url, "http://localhost");
  const path = url.pathname.replace(/\/$/, "") || "/";
  const key = authenticate(db, req.headers.authorization);

  if (req.method === "POST" && path === "/emails") {
    const body = await readJsonBody(req);
    const email = await sendEmail(db, transport, key.id, body, {
      idempotencyKey: req.headers["idempotency-key"],
    });
    return send(res, 200, { id: email.id });
  }

  const emailMatch = /^\/emails\/([^/]+)$/.exec(path);
  if (req.method === "GET" && emailMatch) {
    return send(res, 200, getEmail(db, key.id, emailMatch[1]));
  }

  if (path === "/api-keys") {
    requireFullAccess(key);
    if (req.method === "POST") {
      return send(res, 201, createApiKey(db, await readJsonBody(req)));
    }
    if (req.method === "GET") {
      return send(res, 200, { data: listApiKeys(db) });
    }
  }

  const keyMatch = /^\/api-keys\/([^/]+)$/.exec(path);
  if (req.method === "DELETE" && keyMatch) {
    requireFullAccess(key);
    return send(res, 200, revokeApiKey(db, keyMatch[1]));
  }

  throw notFound(`No route for ${req.method} ${path}.`);
}

export function createServer({ db, transport }) {
  return createHttpServer((req, res) => {
    route(db, transport, req, res).catch((err) => {
      if (err instanceof ApiError) return send(res, err.statusCode, err.toJSON());
      send(res, 500, { statusCode: 500, name: "internal_error", message: err?.message ?? "Internal error." });
    });
  });
}
