import { join } from "node:path";
import { openDatabase } from "./src/db.js";
import { createMailer } from "./src/mailer.js";
import { createServer } from "./src/server.js";
import { createApiKey, listApiKeys } from "./src/apiKeys.js";

const port = Number(process.env.PORT ?? 3000);
// Anchor the default DB to this directory so it lands here regardless of cwd.
const db = openDatabase(process.env.DATABASE_PATH ?? join(import.meta.dirname, "email-api.db"));

// SMTP_URL like smtp://user:pass@host:587 sends for real; without it we fall
// back to nodemailer's JSON transport so the demo runs with zero config.
const transport = createMailer(process.env.SMTP_URL || undefined);

// Seed a full-access key on first boot and print it once, the way a dashboard
// would surface the first key for a new account.
if (listApiKeys(db).length === 0) {
  const { token } = createApiKey(db, { name: "default" });
  console.log(`\nSeeded API key (shown once): ${token}\n`);
}

createServer({ db, transport }).listen(port, () => {
  console.log(`email-api listening on http://localhost:${port}`);
  console.log(`Send: curl -X POST http://localhost:${port}/emails \\`);
  console.log(`  -H "Authorization: Bearer re_..." -H "Content-Type: application/json" \\`);
  console.log(`  -d '{"from":"you@yours.com","to":"them@theirs.com","subject":"hi","text":"hello"}'`);
});
