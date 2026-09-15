# Team2

Mobile-first app for **attendance, leave, permission and field visits**.

- Folder: `D:\Team2`
- Local dev: `python server.py` → <http://127.0.0.1:8127/>
- Live: <https://team2-ruddy.vercel.app> (Vercel login required)
- Production host: **team2.carloo.in** — attached to the project, *waiting on one DNS record*
- Backend: existing Supabase project `carloo-order-management`
  (`thmszlxepqkrcqavlilq`), own **`team2` schema**
- Version: 0.2.0 (set in `window.APP_CFG` at the top of `index.html`)

Same house pattern as Mono / Muthu's / Asset: one plain `index.html`, no build
step, Supabase JS from the CDN, `db/*.sql` as the SQL source of truth.

---

## Where things are

| File | What it is |
|---|---|
| `index.html` | The whole app — shell, login, menu grid, Google Maps helper |
| `server.py` | Local static server on port 8127, caching disabled |
| `manifest.webmanifest` | PWA manifest so it installs to a phone home screen |
| `vercel.json` | No build, no cache |
| `.vercelignore` | Keeps `db/`, `server.py`, the README and `.env*` off the public site |
| `db/01…06_*.sql` | Every migration already applied, in order |

Ports in use across the apps: Mono 1.0 `8123`, Mono 2.0 `8124`, Muthu's `8125`,
Asset `8126`, **Team2 `8127`**, prodwatch `8777`.

---

## Status — what is built

**Built:** the shell. Login, session, the menu grid, hash routing, and the
permission matrix deciding which tiles a role sees.

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

**Every menu is an empty placeholder.** They get built one at a time, once the
behaviour for that menu is described. The 22 menus are:

| Group | Menus |
|---|---|
| Daily | Punch In/Out · My Attendance · Visits · Live Tracking |
| Requests | Leave · Permission · Regularisation · Approvals |
| Masters | Customer/Site · Visit Purpose · Location · Department · Designation · Shift · Holiday · Leave Type · Role |
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

Note the same limit Asset hit: **creating logins from inside the app needs the
service-role key**, which cannot live in a browser app. The User Master menu will
need an edge function before it can create users.

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
