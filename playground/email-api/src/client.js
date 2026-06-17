// A tiny SDK shaped after the official `resend` package: construct with an API
// key, then call `client.emails.send(...)` / `client.apiKeys.create(...)`. Every
// method resolves to `{ data, error }` instead of throwing, so callers branch on
// `error` the same way they would with Resend.
export class EmailClient {
  constructor(apiKey, { baseUrl = "http://localhost:3000" } = {}) {
    this.apiKey = apiKey;
    this.baseUrl = baseUrl.replace(/\/$/, "");

    this.emails = {
      send: (payload, options = {}) =>
        this.#request("POST", "/emails", { body: payload, idempotencyKey: options.idempotencyKey }),
      get: (id) => this.#request("GET", `/emails/${id}`),
    };

    this.apiKeys = {
      create: (payload) => this.#request("POST", "/api-keys", { body: payload }),
      list: () => this.#request("GET", "/api-keys"),
      remove: (id) => this.#request("DELETE", `/api-keys/${id}`),
    };
  }

  async #request(method, path, { body, idempotencyKey } = {}) {
    const headers = { authorization: `Bearer ${this.apiKey}` };
    if (body !== undefined) headers["content-type"] = "application/json";
    if (idempotencyKey) headers["idempotency-key"] = idempotencyKey;

    const res = await fetch(`${this.baseUrl}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });

    const data = res.status === 204 ? null : await res.json();
    return res.ok ? { data, error: null } : { data: null, error: data };
  }
}
