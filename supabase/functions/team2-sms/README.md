# team2-sms

Deployed to `thmszlxepqkrcqavlilq`, `verify_jwt = false` (the caller's token is checked inside).

SMV SMS gateway, DLT-registered:
`GET http://smvsms.smvnetwork.in/http-tokenkeyapi.php?authentic-key=&senderid=&route=&number=&message=&templateid=`

- **http only** — https does not connect, so the key is unencrypted between the function
  and the gateway. It never reaches a browser. Ask SMV for an https endpoint.
- Admins only. The message is always built from the stored DLT template body with
  `{#var#}` filled in order — callers only supply values (max 30 chars each), because
  DLT rejects any text that differs from the registered template.
- Takes a 10-digit Indian mobile (strips a leading 91 or 0).
- Gateways often reply HTTP 200 on failure, so replies containing words like error /
  invalid / insufficient are logged as failed. The raw reply is kept in `team2.sms_log`.
