// team2-sms — Team2's SMS sender (SMV SMS gateway, DLT-registered).
//
//   GET http://smvsms.smvnetwork.in/http-tokenkeyapi.php
//       ?authentic-key=<key>&senderid=<CARLOO>&route=<1>&number=<mobile>
//       &message=<exact DLT template text with {#var#} filled>&templateid=<DLT id>
//
// The gateway only answers over plain http — https does not connect — so the key is
// unencrypted between this function and SMV. It never reaches a browser.
//
// Indian DLT rules reject any text that differs from the registered template, so the
// message is always built from the stored template body; callers only supply values.
// Every attempt is written to team2.sms_log.
//
// verify_jwt is off on purpose: the caller's token is verified below.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";

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

// SMS gateways often answer HTTP 200 even when they reject a message.
const FAILURE_WORDS = /(error|invalid|fail|insufficient|incorrect|wrong|denied|not\s+allowed|blocked|unauthori[sz]ed)/i;

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

  const { data: caller } = await team2
    .from("profiles").select("role, active").eq("id", callerId).maybeSingle();
  if (!caller || !caller.active || !["superadmin", "admin"].includes(caller.role)) {
    return json({ error: "Admins only" }, 403);
  }

  let body: Record<string, any>;
  try { body = await req.json(); } catch { return json({ error: "Bad request" }, 400); }
  if (body.action !== "send") return json({ error: "Unknown action" }, 400);

  // ---- load settings ----
  const { data: row } = await team2
    .from("integrations").select("config, secret, enabled").eq("provider", "sms").maybeSingle();
  if (!row) return json({ error: "SMS is not set up" }, 400);
  if (!row.enabled) return json({ error: "SMS is switched off in Settings" }, 400);

  const cfg = row.config ?? {};
  const key = String(row.secret?.api_key ?? "").trim();
  const apiUrl = String(cfg.api_url ?? "").trim();
  const sender = String(cfg.sender_id ?? "").trim();
  const route = String(cfg.route ?? "").trim();
  if (!key || !apiUrl || !sender) return json({ error: "SMS settings are incomplete (key, API URL or sender ID)" }, 400);

  const templateKey = String(body.template ?? "");
  const tpl = cfg.templates?.[templateKey];
  if (!tpl) return json({ error: "That SMS template is not registered" }, 400);

  // ---- number: the gateway takes the 10-digit Indian mobile ----
  let to = String(body.to ?? "").replace(/\D/g, "");
  if (to.length === 12 && to.startsWith("91")) to = to.slice(2);
  if (to.length === 11 && to.startsWith("0")) to = to.slice(1);
  if (!/^[6-9]\d{9}$/.test(to)) return json({ error: "Enter a valid 10-digit Indian mobile number" }, 400);

  // ---- fill {#var#} in order, from the registered body only ----
  const vars: string[] = Array.isArray(body.vars) ? body.vars.map((v: unknown) => String(v ?? "").trim()) : [];
  const slots = (String(tpl.body).match(/\{#var#\}/g) ?? []).length;
  if (vars.length !== slots) {
    return json({ error: `"${tpl.name}" needs exactly ${slots} value(s), got ${vars.length}` }, 400);
  }
  if (vars.some((v) => !v)) return json({ error: "Every placeholder needs a value" }, 400);
  if (vars.some((v) => v.length > 30)) return json({ error: "A DLT variable can be at most 30 characters" }, 400);
  let i = 0;
  const message = String(tpl.body).replace(/\{#var#\}/g, () => vars[i++]);

  // ---- send ----
  let status = "failed";
  let error: string | null = null;
  let reply = "";
  try {
    const target = new URL(apiUrl);
    target.searchParams.set("authentic-key", key);
    target.searchParams.set("senderid", sender);
    if (route) target.searchParams.set("route", route);
    target.searchParams.set("number", to);
    target.searchParams.set("message", message);
    if (tpl.template_id) target.searchParams.set("templateid", String(tpl.template_id));

    const res = await fetch(target.toString(), { method: "GET" });
    reply = (await res.text().catch(() => "")).trim().slice(0, 500);

    if (!res.ok) error = reply || `HTTP ${res.status}`;
    else if (FAILURE_WORDS.test(reply)) error = reply;
    else status = "sent";
  } catch (e) {
    error = (e as Error).message;
  }

  await team2.from("sms_log").insert({
    template: templateKey,
    to_number: to,
    message,
    status,
    error,
    provider_reply: reply || null,
    sent_by: callerId,
  });

  if (status !== "sent") return json({ error: error || "Send failed", reply }, 502);
  return json({ ok: true, to, message, reply });
});
