# team2-whatsapp

Deployed to `thmszlxepqkrcqavlilq`, `verify_jwt = false` (the caller's token is checked inside).

Team2's **own** whatapi.in account — separate from Muthu's; never shares config or senders.

`POST { action: "send", template: "message" | "otp", to, vars: [...], medialink? }`
→ `GET https://webhook.whatapi.in/webhook/<id>?number=&message=<v1,v2,…>&medialink=`

- Admins only (active Team2 `superadmin`/`admin`).
- Webhook id per template comes from `team2.integrations.secret.webhooks[template]`.
- Value count must equal the template's `variables`; values may not contain commas
  (whatapi.in splits `message` on them); image-header templates need an https link.
- 10-digit numbers get `91` prefixed. Every attempt is logged to `team2.whatsapp_log`.
