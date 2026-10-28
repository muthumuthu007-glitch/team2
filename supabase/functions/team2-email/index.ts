// team2-email — Team2's email sender (SMTP, mms@carloo.in on Netcore).
//
// Runs on our own server now, not Supabase. Supabase blocked outbound 25 and 587
// and allowed only 465; our own box allows 587 too, so only port 25 is refused
// here (almost every VPS provider blocks it to stop spam). The configured port is
// 465 (implicit TLS), which is what smtp3.netcore.co.in uses.
//
// The SMTP password lives in team2.integrations.secret.password (admin-only) and
// is used only here. Every attempt is written to team2.email_log.
//
// verify_jwt is off on purpose: the caller's token is verified below.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

const EMAIL_RE = /^[^\s@,;]+@[^\s@,;]+\.[^\s@,;]+$/;

function withTimeout<T>(p: Promise<T>, ms: number, what: string): Promise<T> {
  return Promise.race([
    p,
    new Promise<T>((_, rej) => setTimeout(() => rej(new Error(`${what} timed out after ${ms / 1000}s`)), ms)),
  ]);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Use POST" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return json({ error: "Function is not configured" }, 500);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const team2 = admin.schema("team2");

  // ---- caller must be an active Team2 admin ----
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Not signed in" }, 401);
  const { data: authData, error: authErr } = await admin.auth.getUser(token);
  if (authErr || !authData?.user) return json({ error: "Not signed in" }, 401);
  const callerId = authData.user.id;

  const { data: caller, error: callerErr } = await team2
    .from("profiles").select("role, active").eq("id", callerId).maybeSingle();
  if (callerErr) return json({ error: "Could not check your access: " + callerErr.message }, 500);
  if (!caller || !caller.active || !["superadmin", "admin"].includes(caller.role)) {
    return json({ error: "Admins only" }, 403);
  }

  let body: Record<string, any>;
  try { body = await req.json(); } catch { return json({ error: "Bad request" }, 400); }
  if (body.action !== "send_test") return json({ error: "Unknown action" }, 400);

  const to = String(body.to ?? "").trim();
  if (!EMAIL_RE.test(to)) return json({ error: "Enter one valid email address" }, 400);

  // ---- settings ----
  const { data: row, error: rowErr } = await team2
    .from("integrations").select("config, secret, enabled").eq("provider", "email").maybeSingle();
  if (rowErr) return json({ error: "Could not read email settings: " + rowErr.message }, 500);
  if (!row) return json({ error: "Email is not set up" }, 400);
  if (!row.enabled) return json({ error: "Email is switched off in Settings" }, 400);

  const c = row.config ?? {};
  const host = String(c.smtp_host ?? "").trim();
  const port = Number(c.smtp_port ?? 465);
  const user = String(c.username ?? "").trim();
  const pass = String(row.secret?.password ?? "");
  const fromEmail = String(c.from_email ?? user).trim();
  const fromName = String(c.from_name ?? "Team2").trim().replace(/["<>]/g, "");
  if (!host || !user || !pass) return json({ error: "SMTP host, username or password is missing" }, 400);
  if (port === 25) {
    return json({ error: "Port 25 is blocked for outgoing mail — use 465 (SSL/TLS) or 587 (STARTTLS)" }, 400);
  }

  const subject = "Team2 test email";
  const when = new Date().toLocaleString("en-IN", { timeZone: "Asia/Kolkata" });
  const text = `This is a test email from Team2.\n\nSent ${when} IST through ${host}:${port} as ${user}.\n` +
               `If you can read this, automatic report emails will be able to go out.`;
  const html = `<div style="font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#1b2033">` +
               `<h2 style="margin:0 0 10px;color:#2f4bd0">Team2 test email</h2>` +
               `<p>This is a test email from Team2.</p>` +
               `<p style="color:#666">Sent ${when} IST through ${host}:${port} as ${user}.</p>` +
               `<p>If you can read this, automatic report emails will be able to go out.</p></div>`;

  // ---- send ----
  let status = "failed";
  let error: string | null = null;
  const client = new SMTPClient({
    connection: { hostname: host, port, tls: port === 465 || c.security === "SSL/TLS", auth: { username: user, password: pass } },
  });
  try {
    await withTimeout(
      client.send({ from: `${fromName} <${fromEmail}>`, to, subject, content: text, html }),
      30000, "Sending",
    );
    status = "sent";
  } catch (e) {
    error = String((e as Error)?.message ?? e).slice(0, 400);
  } finally {
    try { await withTimeout(client.close(), 5000, "Closing the connection"); } catch { /* ignore */ }
  }

  await team2.from("email_log").insert({
    kind: "test", to_address: to, subject, status, error, sent_by: callerId,
  });

  if (status !== "sent") return json({ error: error || "Send failed" }, 502);
  return json({ ok: true, to });
});
