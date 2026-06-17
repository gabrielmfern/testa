import { randomBytes, randomUUID } from "node:crypto";

// Emails and API keys are identified by UUIDs, matching Resend's public ids.
export const newId = () => randomUUID();

// API tokens look like `re_<urlsafe>` — the `re_` prefix is Resend's convention.
export const newApiToken = () => `re_${randomBytes(24).toString("base64url")}`;
