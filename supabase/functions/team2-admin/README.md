# team2-admin edge function

Deployed to Supabase project `thmszlxepqkrcqavlilq` (`verify_jwt = false`).

**Why it exists:** `team2.profiles.id` references `auth.users`, and creating an auth
user needs the **service-role key**, which must never reach a browser. The app calls
this function instead; it re-checks the caller with the service-role client and
refuses anyone who is not an active Team2 `superadmin`/`admin`.

`verify_jwt` is off deliberately — the token is verified inside the function, which
also works with `sb_publishable_*` keys (the platform check was unreliable there;
Mono hit the same thing).

## Actions

| Action | Body | Does |
|---|---|---|
| `create_user` | `username` (10-digit mobile), `password`, `profile{}` | Creates the auth user + profile. Rolls back the auth user if the profile insert fails. |
| `create_many` | `users[]` of the above, max 500 | Same, one at a time, returning `created` and `failed[]`. |
| `set_password` | `user_id`, `password` | Resets a password. |

Only a fixed allow-list of profile columns is written; anything else in `profile` is
ignored, so a caller cannot set columns the form does not expose.

## Redeploying

The live source is the copy in Supabase. To change it, edit there or redeploy via the
Supabase MCP `deploy_edge_function`, keeping `verify_jwt: false`.
