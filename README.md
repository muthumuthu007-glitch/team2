# Team2

Mobile-first app for **attendance, leave, permission and field visits**.

- Folder: `D:\Team2`
- Local dev: `python server.py` → <http://127.0.0.1:8127/>
- Live: <https://team2-ruddy.vercel.app> (Vercel login required)
- Production host: **team2.carloo.in** — attached to the project, *waiting on one DNS record*
- Backend: existing Supabase project `carloo-order-management`
  (`thmszlxepqkrcqavlilq`), own **`team2` schema**
- Version: 0.9.9 (set in `window.APP_CFG` at the top of `index.html`)

Same house pattern as Mono / Muthu's / Asset: one plain `index.html`, no build
step, Supabase JS from the CDN, `db/*.sql` as the SQL source of truth.

---

## Where things are

| File | What it is |
|---|---|
| `index.html` | The whole app — shell, login, left tree menu, Google Maps helper |
| `server.py` | Local static server on port 8127, caching disabled |
| `manifest.webmanifest` | PWA manifest so it installs to a phone home screen |
| `vercel.json` | No build, no cache |
| `.vercelignore` | Keeps `db/`, `server.py`, the README and `.env*` off the public site |
| `db/01…06_*.sql` | Every migration already applied, in order |

Ports in use across the apps: Mono 1.0 `8123`, Mono 2.0 `8124`, Muthu's `8125`,
Asset `8126`, **Team2 `8127`**, prodwatch `8777`.

---

## Status — what is built

**Built:** the shell. Login, session, a **left sidebar tree menu** (v0.3.0), hash
routing, and the permission matrix deciding which menus a role sees.

The tree shows Home, then each group (Daily, Requests, Masters, Reports, Admin) as a
collapsible branch with a count; the open menu is highlighted and its branch always
expands. Collapsed branches are remembered per browser. Under 900px wide the tree
becomes a slide-in drawer (hamburger, scrim, Esc to close) so it works on phones.

**Login page** (v0.2.0) is modelled on the Carloo Tex *Field Force Management*
login, with the **Gate** tab deliberately removed. Three tabs:

| Tab | Who gets in |
|---|---|
| Admin | `superadmin`, `admin`, `manager` — anyone else is signed straight back out and told to use Team |
| Team | Any active profile |
| Visitor | Nobody yet — there is no visitor role or module, so the form refuses to sign in |

The role rule is checked only at sign-in; a reload with a live session goes
straight in. The last tab used is remembered per browser. The Carloo mark is
set in type (Calibri) — swap in the real logo file when there is one.

**Three masters are built** (v0.4.0 – v0.5.0):

| Menu | What it does |
|---|---|
| **Unit** | Name, address (Google Places search), city, pincode, active. Geofence is a **circle** (drag it, or set a radius) or a **polygon** you draw by clicking corners on the map, plus a **buffer** in metres. Stored in `team2.locations`. |
| **Department** | Name + active, with **Export**, **Import** and a downloadable import template. |
| **Designation** | Same screen as Department, different table. |
| **Supplier** | Was "Customer / Site" (v0.9.9), `team2.parties` with `party_type = 'supplier'`. Code, name, address, phone, status; **Upload list** reads the company supplier sheet (.xlsx/.xls/.csv — columns *Supplier Name, Address, Phone No*), skips names already present, and imports in batches of 500. Export and Template write the same layout. Shows the first 300 matches; search narrows it. |
| **Visit Purpose** | Same screen again (v0.9.8), `team2.visit_purposes` — six starter purposes were seeded. |
| **Role** | Name, description, **Full access** (bypasses the matrix) and active, with Export / Import / template. Stored in `team2.roles`. |
| **Permissions** | The role × menu matrix (v0.8.0) — see below. |
| **User Master** | Staff table (v0.9.0): name, staff ID, mobile, role, department, designation, Report 1/2/3, **Unit**, schedule, status. Search by name/mobile/staff ID, six filters, a result count, Add staff, Edit, Set password, Activate/Deactivate, Export, Template and Bulk import. No Rate/Km column. |
| **Schedule** | Was "Shift". Name, day check-in/out, three tea breaks (window + minutes), lunch (window + minutes) and permission hours per 26-day month. Shows how many staff are on each schedule, with an **In use only** filter, plus Export / Template / Import. Stored in `team2.shifts`. |

Department and Designation share one `simpleMaster(host, cfg)` function — another
name-only master is a config plus a table, not new screen code. Import matches on
**name** (case-insensitive), skips names that already exist or repeat within the
file, ignores blank rows, and reports the counts before you commit. `code` in an
imported file is ignored: codes are generated (`DEP-001`, `LOC-001`).

**Settings** (v0.7.0, admin only) holds four sections: **Google API** (the Maps
browser key), **WhatsApp API**, **SMS settings** and **Email — automatic reports**.

The Maps key is entered there, not in this file, so it never reaches the repo.
`APP_CFG.gmapsKey` still wins if set. After saving a key, reload the app.

**Where the credentials live, and why it matters:**

| Stored in | Who can read it | What goes there |
|---|---|---|
| `team2.app_settings` | **every signed-in user** | Maps browser key, tracking interval, non-secret toggles |
| `team2.integrations` | **admins only** (RLS `is_admin()` on ALL commands) | WhatsApp token, SMS API key, SMTP password |

Never move a token into `app_settings` — ordinary staff can read that table through
the API. Secret boxes show "· saved" and stay blank; typing replaces, blank keeps.

### WhatsApp (v0.9.3)

**Team2's WhatsApp account is separate from Muthu's.** Muthu's uses whatapi.in with a
per-template webhook (`muthus.whatsapp_config`, `muthus-whatsapp`). None of that is
shared or reused here.

Team2's provider is recorded as **whatapp.in**; its access key is stored in
`team2.integrations.secret.access_token` (admin-only). Two approved templates are
registered in `integrations.config.templates` and shown as previews in Settings:

| Key | Called | Template | Placeholders | Use |
|---|---|---|---|---|
| `message` | **Message format** | `order details 0126` | `{{1}}`–`{{4}}`, image header | any general message |
| `otp` | **OTP format** | `otp alert 48157` | `{{1}}` = the code, Copy code button, expires in 2 min | login OTP, visitor OTP |

The bodies are stored word for word as approved (including "Thanks you") — a send
must match the approved template, so do not "correct" them.

The provider is **whatapi.in** (Team2's own account). Each template gets a **webhook
link** from the whatapi.in panel; paste it into the box under the template in Settings and
**Send test** works. Sending goes through the `team2-whatsapp` edge function — see
`supabase/functions/team2-whatsapp/README.md`. Webhook links are send credentials, stored
admin-only in `integrations.secret.webhooks`.

### SMS (v0.9.5)

SMV SMS gateway, DLT-registered: sender **CARLOO**, entity `1701178236966573485`, route 1.
One template, **OTP SMS** (`Otp Sms`, DLT template `1707178402149487842`):

> Your Verification code is {#var#}. It is valid for 10 minutes, Do not share it with anyone - CARLOO

Settings › SMS shows it with a **Send test SMS** panel and the last 10 sends. Sending goes
through the `team2-sms` edge function. **The gateway is http-only**, so the key is
unencrypted between our server and SMV — worth asking them for https.

Settings saves now **merge** into the stored config, so fields the form does not show
(the templates) are never wiped by a Save.

### Email (v0.9.6)

`mms@carloo.in`, hosted on **Netcore** (MX `cluster*.netcore.co.in`). Verified by
connecting, not guessed:

| | Host | Port | Evidence |
|---|---|---|---|
| Outgoing (SMTP) | `smtp3.netcore.co.in` | 465, SSL/TLS | valid cert, greets as `ncismumsmtp1` |
| Incoming (POP3) | `pop3.netcore.co.in` | 995, SSL/TLS | valid cert, greets as `ncismumpop3` |

Both carry the same `ncismum` platform prefix. **Not** `mail.carloo.in` — it resolves but
answers on no port at all. **Not** `smtps.netcore.co.in` — that is Netcore Cloud's separate
bulk-mail product. The password is entered by the user in Settings; email stays switched
off until they tick Enabled. **Send test email** (v0.9.8) goes through the `team2-email`
edge function on port 465 and logs to `team2.email_log`.

**Nothing sends yet.** A browser cannot hold a sending credential safely, so WhatsApp,
SMS and email delivery each need an edge function. The screen says so.

**Note on `DrawingManager`:** Google removed it from the Maps JS API in 3.65, so
the polygon is drawn by hand — map clicks push vertices onto an editable
`Polygon`, with Undo point and Clear. Don't reintroduce `DrawingManager`.

**The remaining menus are empty placeholders.** They get built one at a time, once
the behaviour for that menu is described. The 22 menus are:

| Group | Menus |
|---|---|
| Daily | Punch In/Out · My Attendance · Visits · Live Tracking |
| Requests | Leave · Permission · Regularisation · Approvals |
| Masters | Customer/Site · Visit Purpose · **Unit** · **Department** · **Designation** · **Schedule** · Holiday · Leave Type · Role |
| Reports | Reports · Travel/Distance |
| Admin | User Master · Permissions · Settings |

The **database behind all of them already exists** (22 tables) — so a menu is a
screen to build, not a schema to design.

---

## The database

Everything lives in the `team2` schema. `pgrst.db_schemas` on role
`authenticator` is now `public, graphql_public, mono, muthus, asset, team2` —
**the other three must stay in that list or those apps break.**

### Tables

**People & masters** — `profiles`, `locations`, `departments`, `designations`,
`roles`, `shifts`, `holidays`, `role_permissions`

**Attendance** — `attendance_punches` (raw events), `attendance` (one derived
row per employee per day), `regularisations` (fix a missed punch)

**Leave & permission** — `leave_types`, `leave_balances`, `leave_requests`,
`permission_requests` ("permission" = short leave in minutes, inside one day)

**Visits & travel** — `parties` (customer/site), `visit_purposes`, `visits`,
`visit_photos`, `visit_tracks` (GPS breadcrumbs), `trips` (day travel summary)

**Config** — `app_settings` (tracking interval, geofence default, permission caps,
selfie-on-punch, week start)

### Unit geofences

`team2.locations` keeps its table name on purpose — `profiles.location_id`, the RLS
helpers and `role_permissions.menu_id = 'locations'` all key on it. Only the app
label says "Unit". The geofence columns:

| Column | Meaning |
|---|---|
| `geofence_type` | `circle` or `polygon` |
| `lat` / `lng` | circle centre; for a polygon, the centroid (used to centre the map) |
| `geofence_m` | circle radius in metres |
| `geofence_polygon` | `jsonb` array of `{"lat":…,"lng":…}`, at least 3, enforced by a check constraint |
| `geofence_buffer_m` | extra tolerance in metres outside either shape (0–5000) |

### Schedules

`team2.shifts` likewise keeps its name (`profiles.shift_id`, the attendance trigger
and `menu_id = 'shifts'`). Added for the Schedule screen: `tea1_from/to/min`,
`tea2_*`, `tea3_*`, `lunch_from/to/min` and `permission_hours` (per 26-day month).

Staff **link** to a schedule by `profiles.shift_id`; there is no per-person copy, so
editing a schedule applies to everyone on it immediately. The button says
"Update & propagate" to match the agreed design, but nothing is copied.

**Not in the form yet:** `week_offs`, `grace_in_min`, `grace_out_min`,
`half_day_min`, `full_day_min`, `night_shift`. They keep their defaults and the
attendance trigger still uses grace/half/full — say the word to expose them.

### Things worth knowing

- **A punch writes the day row for you.** Insert into `attendance_punches` and a
  trigger (`team2.sync_attendance_day`) recomputes first-in, last-out, worked
  minutes, late, early-out and OT against the employee's shift. A `status` set by
  hand (leave / holiday / on duty) is **not** overwritten by later punches.
- **The business day is IST**, defined once in `team2.biz_date()`.
- **Punches are never edited** — RLS allows insert-by-self and admin-only update.
  A wrong punch is corrected through `regularisations`.
- **`team2.distance_m(lat1,lng1,lat2,lng2)`** gives straight-line metres — used
  for geofence checks and as the fallback when there's no Google road distance.
- `visit_tracks` is append-only and will grow fast at a 3-minute interval
  (~200 rows/person/day). Plan a retention rule before this is on many phones.

### Who can see what

`profiles.reporting_to` builds the reporting tree, and
`team2.in_my_team()` walks it to **any depth** — a manager sees everyone under
them, not just direct reports.

The role permission matrix (`role_permissions`, one row per role × menu) is
**enforced in RLS**, not just in the UI:

| Level | Means |
|---|---|
| `none` | Menu hidden |
| `view_own` / `edit_own` | Own records + the team below you |
| `view_all` / `edit_all` | Everything |

### The Permissions screen (Admin › Permissions)

A matrix: one row per menu (grouped Daily / Requests / Masters / Reports / Admin),
one column per **active role** from the Role master. Each cell is a dropdown —
No access, View – Own, View – All, Edit – Own, Edit – All — writing
`team2.role_permissions`, which is what `team2.matrix_access()` reads in RLS.

Columns that are **locked with a tick**: Superadmin (built in, always all rights) and
any role flagged **Full access** (`roles.is_admin`) in the Role master.

Changes are staged, not saved per click: edited cells are outlined, the button counts
them ("Save 3 changes"), and setting a cell back to its original value drops it from
the batch. Saving does one upsert on `(role_id, menu_id)`. A user picks up new rights
on their next sign-in or reload.

Rules that sit above the matrix and can't be configured away:

- `superadmin` / `admin` bypass the matrix, so a bad config can't lock everyone out.
- A role with **no matrix row** falls back to readable — half-configured is not broken.
- **You always see your own records**, whatever the matrix says.
- Requests are editable by the raiser **only while `pending`**; approving is for
  admins and the people above you in the reporting tree.

---

## Google Maps

`window.APP_CFG.gmapsKey` at the top of `index.html` is **empty**. Until a key
goes in there, every map feature is off and the app records raw lat/lng only —
nothing breaks.

Create a browser key in Google Cloud, enable these four APIs, and restrict it by
HTTP referrer to `team2.carloo.in` and `127.0.0.1:8127`:

| API | Used for |
|---|---|
| Maps JavaScript API | Loads the library; the map view |
| Geocoding API | Turn a punch/check-in lat-lng into a street address |
| Places API | Address autocomplete when adding a customer or site |
| Distance Matrix API | Road km between visit points, for travel claims |

The `GMaps` helper in `index.html` already wraps all four —
`GMaps.here()` (browser GPS, needs no key), `.address()`, `.autocomplete()`,
`.roadKm()`. Each resolves to `null` when there's no key, so screens can be
written once and light up when the key lands.

**Billing:** all four are paid APIs past the free monthly credit. Distance Matrix
is the expensive one — cache the km on `trips.google_distance_km` rather than
recomputing.

---

## Logins

Username is the **mobile number**, mapped to `<mobile>@team2.app` for GoTrue.
Passwords are **never** written into this repo — same rule as Muthu's and Asset.

The superadmin exists: **`9894021299`** (emp_code `01`, name "Admin", Admin role,
General shift). Its password was set directly on the database and is not recorded
here. To create more logins by hand, or to reset this one, the SQL is at the
bottom of `db/06_expose_and_seed.sql`.

**Creating logins goes through the  edge function** (v0.9.0) — see
`supabase/functions/team2-admin/README.md`. A browser cannot hold the service-role
key, so the function does it and re-checks that the caller is an active Team2 admin.
Verified: calls with no token, a bogus token and the publishable key are all rejected
with 401 and create nothing.

**Staff are never deleted** — User Master offers Activate/Deactivate instead.
Deleting a profile would cascade and take that person's attendance, leave and visit
history with it.

**Report 1 is the only level that grants visibility.** `reporting_to` is what
`team2.in_my_team()` walks; `reporting_to_2`/`_3` are escalation contacts only.

---

## Deploying

**Deployed 2026-09-06.** Vercel project `team2`
(`prj_xjBr2oWnwUg2UdWocaQNbGcpzu5i`) under `muthumuthu007-9344s-projects`,
production deployment live at:

- <https://team2-ruddy.vercel.app>
- <https://team2-muthumuthu007-9344s-projects.vercel.app>

Those `*.vercel.app` URLs are behind Vercel Authentication
(`ssoProtection: all_except_custom_domains`), so only someone signed in to the
Vercel account sees them. That is the default and it is the right setting —
**custom domains are exempt**, so `team2.carloo.in` will be public once DNS
points at Vercel. Do not disable it to "make the site work".

### team2.carloo.in — waiting on one DNS record

The domain is already attached to the project. The only thing left:

    A    team2.carloo.in    76.76.21.21

It currently resolves to **172.66.2.113 / 162.159.142.117 (Cloudflare)**, which
is why HTTPS fails the TLS handshake — nothing holds a certificate for it.
Change that record at **BigRock** (`carloo.in` still uses dns1-4.bigrock.in) to
the `A` record above, the same one `asset.carloo.in` uses. Vercel issues the
certificate automatically once it sees it, usually within minutes.

Check progress with:

    npx vercel@latest domains inspect team2.carloo.in

### Pushing updates

From `D:\Team2`:

    npx vercel@latest --prod

The folder is linked (`.vercel/project.json`), so it goes straight to the `team2`
project — no prompts, and no risk of the old trap where "Search all projects"
silently linked a folder to `carloo-order-management`.

**Correction to earlier notes:** project *creation* and *domain attachment* both
worked here via the Vercel CLI, which is logged in as `muthumuthu007-9344`.
The 403 recorded against Muthu's and Asset was the **MCP integration token**, not
the CLI. `vercel project add <name>` and `vercel domains add <domain> <project>`
both succeed. Note `vercel --prod --yes` alone fails in this folder — it derives
the project name from the directory `Team2`, and Vercel requires lowercase.

---

## Known gaps

- **No photo storage.** `attendance_punches.selfie_url` and `visit_photos.url`
  are text columns with nothing behind them — a Supabase storage bucket and its
  policies still need creating.
- **No background tracking.** A browser only records GPS while the page is open.
  Continuous tracking with the screen off needs a native wrapper (Capacitor /
  TWA), the same route Mono took for its APK.
- **Nothing computes leave balances.** `leave_balances` is a table an admin fills;
  approving a leave request does not yet deduct from it.
- **Geofencing is advisory.** The app decides `within_geofence` and the database
  believes it. A phone can lie about its location; treat it as a deterrent, not proof.
