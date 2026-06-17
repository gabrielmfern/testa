import nodemailer from "nodemailer";

// Build a nodemailer transport. With no config we use the JSON transport, which
// serializes the message instead of opening a network connection — ideal for
// local dev and tests. Pass real SMTP options for production.
export function createMailer(config) {
  if (!config) {
    return nodemailer.createTransport({ jsonTransport: true });
  }
  return nodemailer.createTransport(config);
}
