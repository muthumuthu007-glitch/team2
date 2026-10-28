# Team2

Mobile-first app for **attendance, leave, permission and field visits**.

- Folder: `D:\Team2`
- Local dev: `python server.py` → <http://127.0.0.1:8127/>
- Live: <https://team2-ruddy.vercel.app> (Vercel login required)
- Production host: **team2.carloo.in** — attached to the project, *waiting on one DNS record*
- Backend: existing Supabase project `carloo-order-management`
  (`thmszlxepqkrcqavlilq`), own **`team2` schema**
- Version: 2.0.1 (set in `window.APP_CFG` at the top of `index.html`)

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
| **Company** | Superadmin only (v0.10.0). Name, address, GST number, email, phone, plus the company's **first admin login** created in the same step. Validates GSTIN (15-char format), email and duplicate names in the app **and** in the database. Companies are deactivated, never deleted. |
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

### Multi-company: what exists and what does NOT

`team2.companies` + `profiles.company_id` exist, and Admin › Company creates a company
with its admin login (through `team2-admin`, action `create_company`, superadmin only —
it deletes the company again if the login cannot be created, so a company is never left
without a way in).

**Data is NOT separated by company yet.** No other table carries `company_id`, and no RLS
policy filters on it, so every admin still sees every company's records. Before a real
customer is signed up, each data table needs a `company_id` column, a default from the
signed-in user's company, and its policy extended with "same company as me". The Company
screen says this in a banner.

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

**Everything runs on our own server.** Vercel, Cloudflare and Supabase Cloud are
out of the picture as of 2026-10-28.

    laptop  D:\Team2
      |  git push
      v
    GitHub  muthumuthu007-glitch/team2
      |  systemd timer checks every 2 minutes
      v
    Webtel server  160.187.251.205
      Caddy  ->  /var/www/team2            (the app)
             ->  127.0.0.1:8000            (Supabase: rest, auth, storage,
                                            functions, realtime)

So **you deploy by pushing to GitHub**. Within two minutes the live site has it.
Nothing else to run.

### One hostname does both

`team2.carloo.in` serves the app *and* the API. Caddy
(`/etc/caddy/Caddyfile`) sends `/rest/*`, `/auth/*`, `/storage/*`,
`/functions/*` and `/realtime/*` to the local Supabase stack and serves
everything else from disk. The certificate is Let's Encrypt, renewed
automatically. There is no separate database hostname — `db.team2.carloo.in` was
abandoned.

### What deploy.sh rewrites

`index.html` in this repo keeps the **Supabase Cloud** url and key on purpose, so
the file stays deployable anywhere. `~/team2-src/deploy.sh` rewrites three things
in the copy it puts in `/var/www/team2`:

| in the repo | on the server |
|---|---|
| `url: "https://thmszlxepqkrcqavlilq.supabase.co"` | `url: "https://team2.carloo.in"` |
| `key: "sb_publishable_…"` | the server's own `ANON_KEY`, read from `/opt/supabase/.env` |
| `version: "2.0.1"` | `version: "2.0.1+<git short sha>"` |

**Do not "fix" the repo copy to point at the server.** The rewrite is the point,
and the stamped version is how you tell which commit is live — it shows on the
login page and in the sidebar footer.

### Server programs (edge functions)

Four of them, in `supabase/functions/`:

| name | what it does |
|---|---|
| `team2-admin` | creates logins, sets passwords, bulk import, creates a company |
| `team2-sms` | SMV gateway, DLT templates |
| `team2-whatsapp` | whatapi.in, Team2's own account |
| `team2-email` | SMTP test send |

They need the service-role key, which must never reach a browser, so they run
server-side and re-check the caller's token themselves. The browser calls them at
`CFG.url + "/functions/v1/<name>"`.

Install them **once** with `./functions-install.sh` on the server; after that
`deploy.sh` copies them into `/opt/supabase/volumes/functions/` on every push.

A working function answers **401 "Not signed in"** when called with no token —
that is the health check. `404 NOT_FOUND` means it was never copied in.

Known rough edge: the functions download their libraries from esm.sh and
deno.land the first time each one runs. That cache lives inside the container, so
it survives a restart but is lost on `recreate` or an image update — the first
call after that is slow, and fails outright if the server has no internet at that
moment. Worth vendoring the libraries before this carries real traffic.

### Doing it by hand

On the server, if you do not want to wait for the timer:

    cd ~/team2-src && ./deploy.sh

Useful checks:

    systemctl list-timers team2-deploy.timer     # is auto-deploy on
    journalctl -u team2-deploy -n 30             # what the last run did
    cd /opt/supabase && ./run.sh status          # are the containers healthy

From anywhere, to see which commit is live:

    curl -s https://team2.carloo.in/ | grep -o 'version: "[^"]*"'

## The phone app

`android/` builds **Team2.apk**. It is a shell, not a copy of the app: it opens
`https://team2.carloo.in` in a WebView, and the server sends the page with
`Cache-Control: no-store`. So **pushing to GitHub updates every phone** — nobody
reinstalls anything. You only rebuild the APK when the shell itself changes:
permissions, splash, icon, package name.

This is deliberately *not* how Mono works. Mono downloads an HTML file from
storage and renders it at a borrowed origin, which welds its APK to that origin
forever and is why Mono cannot leave Supabase without a new APK on every phone.
We own team2.carloo.in, so the shell just loads it.

### What happens on launch

1. **First run only** — Android's own permission prompts, camera then location,
   with no screen of ours in front of them. The system prompt already names the
   permission and the app; a page explaining it first only put a Continue button
   between the person and the question they have to answer anyway. Explaining
   happens where it earns its place: after a refusal.
2. **Every run** — "Checking for updates...", which reads the top of the page
   from the server and shows the build it is about to open
   (`Loading Team2 2.1.0+abc1234...`). The update is therefore finished *before*
   the login page appears.
3. The login page, then the app.

No internet means no launch — there is no offline copy, because the page is
served `no-store`. The shell shows "Could not reach team2.carloo.in" with a
retry button. An offline shell would need a service worker; not built yet.

### Staff only

The shell appends `Team2App/<version>` to the user agent. `index.html` reads
that and **removes the Admin tab** from the login page, so the phone app signs
in as Team or Visitor only. Administration stays on a desktop browser.

### Attachments - no file-type limit

Staff attach whatever the job produced: a gallery photo, a scanned PDF, a
spreadsheet. The page's own `accept="image/*"` would normally restrict the
picker to images, so the shell **widens it to every file type** before opening
it (`widen()` in MainActivity). When the page asked for the camera, that half of
the chooser is left alone, so taking a selfie still works.

A link to a document is handed to whatever app on the phone can open it, via a
`DownloadListener` - a WebView ignores such links otherwise.

### Permissions - two, and both required

| asked for | why |
|---|---|
| Camera | punch-in selfie, visit photos |
| Location (precise) | where a punch or visit happened |

**The app refuses to open until both are granted.** An attendance app whose
punches carry no selfie and no coordinates records nothing anyone can rely on,
so these are not optional. If someone refuses, the shell explains and offers
`Allow` again; once Android stops asking (a firm refusal) it offers **Open
settings** instead and resumes by itself when they come back with the
permissions on.

Android has no way to demand permissions at install time - every runtime
permission can be refused - so refusing to run is the strongest the platform
allows.

**There is no gallery or storage permission.** Attachments go through Android's
own picker, which hands the app the single file the user chose. Asking for
`READ_MEDIA_IMAGES` on top only added the **"Allow limited access"** prompt and
bought nothing, because the app never searches the gallery itself. Removing it
removed that prompt.

**And there is no "save to phone" permission to ask for.** Android has not worked
that way since version 10 - an app can always write its own private storage, and
that is where the WebView keeps GPS readings until they can be sent.

Background location is **not** requested either. Continuous tracking with the
screen off needs `ACCESS_BACKGROUND_LOCATION`, a separate second prompt and a
written justification to Google Play. That belongs with the Live Tracking menu,
not here.

### Building

    powershell -ExecutionPolicy Bypass -File androiduild.ps1

Uses the newest build-tools and platform in the SDK, and Android Studio's bundled
JDK. No Gradle, same as Mono.

**`android/team2-release.keystore` is the only way to ever update an installed
copy.** Android refuses an update signed by a different key. It and
`android/.keystore-pass` are git-ignored - back both up somewhere off this
laptop. Losing them means every phone has to uninstall and start again.

### Icon

The Carloo wordmark is too wide to read at icon size, so the launcher icon is
the interlocking **oo** monogram in Carloo black on white
(`res/drawable/ic_team2_fg.xml`, drawn as a vector so it is sharp at any size).
The full wordmark appears on the splash screen.

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

<!-- deploy check: 2026-10-28, after the execute-bit and false-success fixes -->
