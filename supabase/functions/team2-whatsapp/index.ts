// team2-whatsapp — Team2's WhatsApp sender (whatapi.in).
//
// Team2 has its OWN whatapi.in account, separate from Muthu's. Nothing here reads
// or writes the muthus schema.
//
// whatapi.in gives one webhook per approved template:
//   GET https://webhook.whatapi.in/webhook/<id>?number=<mobile>&message=<v1,v2,...>&medialink=<url>
// `message` carries the template's {{1}},{{2}}... values, comma-separated.
//
// A webhook id is effectively a send credential, so it lives in
// team2.integrations.secret.webhooks and is only ever used here, server-side.
// Every attempt is written to team2.whatsapp_log.
//
// verify_jwt is off on purpose: the caller's token is verified below with the
// service-role client (works with sb_publishable_* keys).

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

const TEMPLATE_KEYS = ["message", "otp"];

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

  // ---- validate the request ----
  const template = String(body.template ?? "");
  if (!TEMPLATE_KEYS.includes(template)) return json({ error: "Unknown template" }, 400);

  let to = String(body.to ?? "").replace(/\D/g, "");
  if (to.length === 10) to = "91" + to;               // Indian mobile without country code
  if (!/^\d{11,15}$/.test(to)) {
    return json({ error: "Enter a mobile number with country code, e.g. 919894021299" }, 400);
  }

  const vars: string[] = Array.isArray(body.vars) ? body.vars.map((v: unknown) => String(v ?? "").trim()) : [];
  const medialink = String(body.medialink ?? "").trim();

  const { data: row } = await team2
    .from("integrations").select("config, secret, enabled").eq("provider", "whatsapp").maybeSingle();
  if (!row) return json({ error: "WhatsApp is not set up" }, 400);
  if (!row.enabled) return json({ error: "WhatsApp is switched off in Settings" }, 400);

  const tpl = row.config?.templates?.[template];
  if (!tpl) return json({ error: "That template is not registered" }, 400);

  const expected = Number(tpl.variables ?? 0);
  if (vars.length !== expected) {
    return json({ error: `"${tpl.name}" needs exactly ${expected} value(s), got ${vars.length}` }, 400);
  }
  if (vars.some((v) => !v)) return json({ error: "Every placeholder needs a value" }, 400);
  // whatapi.in splits `message` on commas, so a comma inside a value would shift
  // every later placeholder. Refuse rather than send a garbled message.
  if (vars.some((v) => v.includes(","))) {
    return json({ error: "Values cannot contain commas — whatapi.in uses them to separate placeholders" }, 400);
  }
  if (tpl.header === "image" && !/^https:\/\//i.test(medialink)) {
    return json({ error: `"${tpl.name}" has an image header — give an https:// image link` }, 400);
  }

  const webhookId = String(row.secret?.webhooks?.[template] ?? "").trim();
  if (!webhookId) {
    return json({ error: `No webhook link saved for "${tpl.name}" yet — add it in Settings` }, 400);
  }

  // ---- send ----
  let status = "failed";
  let error: string | null = null;
  let providerRef: string | null = null;
  let providerReply: unknown = null;
  try {
    const target = new URL(`https://webhook.whatapi.in/webhook/${encodeURIComponent(webhookId)}`);
    target.searchParams.set("number", to);
    target.searchParams.set("message", vars.join(","));
    if (medialink) target.searchParams.set("medialink", medialink);

    const res = await fetch(target.toString(), { method: "GET" });
    const text = await res.text().catch(() => "");
    try { providerReply = text ? JSON.parse(text) : null; } catch { providerReply = text.slice(0, 500); }
    const d = providerReply as Record<string, any> | null;

    if (res.ok) {
      status = "sent";
      providerRef = (d && typeof d === "object" && (d.id || d.message_id || d.messageId)) || null;
    } else {
      error = (d && typeof d === "object" && (d.error || d.message)) || text.slice(0, 300) || `HTTP ${res.status}`;
    }
  } catch (e) {
    error = (e as Error).message;
  }

  await team2.from("whatsapp_log").insert({
    template,
    to_number: to,
    variables: vars,
    medialink: medialink || null,
    status,
    error,
    provider_ref: providerRef ? String(providerRef) : null,
    sent_by: callerId,
  });

  if (status !== "sent") return json({ error: error || "Send failed", provider: providerReply }, 502);
  return json({ ok: true, to, provider_ref: providerRef, provider: providerReply });
});
