# team2-email

Deployed to `thmszlxepqkrcqavlilq`, `verify_jwt = false` (the caller's token is checked inside).

SMTP via `denomailer@1.6.0`, using the settings in `team2.integrations` (provider `email`):
`smtp3.netcore.co.in:465` (implicit TLS), user `mms@carloo.in`, password in `secret.password`.

- **Port 465 only.** Supabase blocks outgoing 25 and 587 from edge functions; the function
  refuses them with a clear message.
- Admins only. `POST { action: "send_test", to }` sends a short test message.
- 30-second send timeout. Every attempt is logged to `team2.email_log`.
