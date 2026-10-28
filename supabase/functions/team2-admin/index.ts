// team2-admin — the only way Team2 can create a login or a company.
//
// team2.profiles.id references auth.users, and creating an auth user needs the
// service-role key, which must never reach a browser. So the browser calls this
// function, which re-checks that the caller is a Team2 admin before doing anything.
//
// verify_jwt is off on purpose: the token is verified here with the service-role
// client, which also works with sb_publishable_* keys.

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

// Only these may be written to a profile from here; anything else is ignored.
const PROFILE_FIELDS = [
  "name", "role", "emp_code", "phone", "email", "active", "date_of_join",
  "role_id", "location_id", "department_id", "designation_id", "shift_id",
  "reporting_to", "reporting_to_2", "reporting_to_3", "company_id",
];

const GSTIN_RE = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function cleanProfile(input: Record<string, unknown> = {}) {
  const out: Record<string, unknown> = {};
  for (const k of PROFILE_FIELDS) {
    if (input[k] !== undefined && input[k] !== "") out[k] = input[k];
  }
  return out;
}

function digits(v: unknown) {
  return String(v ?? "").replace(/\D/g, "");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Use POST" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return json({ error: "Function is not configured" }, 500);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const team2 = admin.schema("team2");

  // ---- who is calling? ----
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Not signed in" }, 401);

  const { data: authData, error: authErr } = await admin.auth.getUser(token);
  if (authErr || !authData?.user) return json({ error: "Not signed in" }, 401);

  const { data: caller, error: callerErr } = await team2
    .from("profiles").select("role, active").eq("id", authData.user.id).maybeSingle();
  if (callerErr) return json({ error: "Could not check your access: " + callerErr.message }, 500);
  if (!caller || !caller.active || !["superadmin", "admin"].includes(caller.role)) {
    return json({ error: "Admins only" }, 403);
  }

  let body: Record<string, any>;
  try { body = await req.json(); } catch { return json({ error: "Bad request" }, 400); }

  // ---- create one login + profile ----
  async function createOne(u: Record<string, any>) {
    const username = digits(u.username);
    if (username.length !== 10) return { ok: false, username, error: "Mobile must be 10 digits" };

    const password = String(u.password ?? "");
    if (password.length < 6) return { ok: false, username, error: "Password must be at least 6 characters" };

    const profile = cleanProfile(u.profile ?? {});
    if (!profile.name) return { ok: false, username, error: "Name is required" };

    const existing = await team2.from("profiles").select("id").eq("username", username).maybeSingle();
    if (existing.data) return { ok: false, username, error: "That mobile number already has a login" };

    const { data: created, error: cErr } = await admin.auth.admin.createUser({
      email: `${username}@team2.app`,
      password,
      email_confirm: true,
      user_metadata: { name: profile.name },
    });
    if (cErr || !created?.user) return { ok: false, username, error: cErr?.message ?? "Could not create the login" };

    const { error: pErr } = await team2
      .from("profiles").insert({ ...profile, id: created.user.id, username });
    if (pErr) {
      // Never leave an auth user with no profile behind.
      await admin.auth.admin.deleteUser(created.user.id);
      return { ok: false, username, error: pErr.message };
    }
    return { ok: true, username, id: created.user.id };
  }

  switch (body.action) {
    case "create_user": {
      const r = await createOne(body);
      return json(r, r.ok ? 200 : 400);
    }

    case "create_many": {
      const list = Array.isArray(body.users) ? body.users : [];
      if (!list.length) return json({ error: "No rows to create" }, 400);
      if (list.length > 500) return json({ error: "Import at most 500 rows at a time" }, 400);
      const results = [];
      for (const u of list) results.push(await createOne(u));
      return json({
        ok: true,
        created: results.filter((r) => r.ok).length,
        failed: results.filter((r) => !r.ok),
      });
    }

    case "set_password": {
      const id = String(body.user_id ?? "");
      const password = String(body.password ?? "");
      if (!id) return json({ error: "Which user?" }, 400);
      if (password.length < 6) return json({ error: "Password must be at least 6 characters" }, 400);

      const target = await team2.from("profiles").select("id").eq("id", id).maybeSingle();
      if (!target.data) return json({ error: "No such user" }, 404);

      const { error } = await admin.auth.admin.updateUserById(id, { password });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    // ---- a company and its first admin login, together ----
    case "create_company": {
      if (caller.role !== "superadmin") {
        return json({ error: "Only the superadmin can create a company" }, 403);
      }

      const c = body.company ?? {};
      const a = body.admin ?? {};
      const name = String(c.name ?? "").trim();
      if (!name) return json({ error: "Enter the company name" }, 400);

      const gstin = String(c.gstin ?? "").trim().toUpperCase();
      if (gstin && !GSTIN_RE.test(gstin)) {
        return json({ error: "That GST number is not in the 15-character format" }, 400);
      }
      const email = String(c.email ?? "").trim();
      if (email && !EMAIL_RE.test(email)) return json({ error: "That company email is not valid" }, 400);

      const clash = await team2.from("companies").select("id").ilike("name", name).maybeSingle();
      if (clash.data) return json({ error: "A company with that name already exists" }, 400);

      const { data: company, error: coErr } = await team2.from("companies").insert({
        name,
        address: String(c.address ?? "").trim() || null,
        gstin: gstin || null,
        email: email || null,
        phone: String(c.phone ?? "").trim() || null,
        active: c.active === false ? false : true,
        created_by: authData.user.id,
      }).select("id, company_code, name").single();
      if (coErr || !company) return json({ error: coErr?.message ?? "Could not create the company" }, 400);

      const r = await createOne({
        username: a.username,
        password: a.password,
        profile: {
          name: String(a.name ?? "").trim() || (name + " admin"),
          role: "admin",
          phone: digits(a.username),
          email: email || null,
          company_id: company.id,
          active: true,
        },
      });
      if (!r.ok) {
        // Do not leave a company with no way in.
        await team2.from("companies").delete().eq("id", company.id);
        return json({ error: "Company not created — " + r.error }, 400);
      }

      return json({ ok: true, company, admin_username: r.username });
    }

    default:
      return json({ error: "Unknown action" }, 400);
  }
});
