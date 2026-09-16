-- Team2 — WhatsApp send log. Applied as migration `team2_whatsapp_log`.
-- Written only by a server-side sender (service role); admins can read it.
-- No insert policy for signed-in users, so the browser cannot fake a "sent" row.
--
-- Team2's WhatsApp account is SEPARATE from Muthu's (muthus.whatsapp_config /
-- muthus-whatsapp). Never share config, tokens or senders between them.

create table if not exists team2.whatsapp_log (
  id            bigserial primary key,
  template      text not null,              -- 'message' | 'otp'
  to_number     text not null,
  variables     jsonb not null default '[]'::jsonb,
  medialink     text,
  status        text not null check (status in ('sent', 'failed')),
  error         text,
  provider_ref  text,
  sent_by       uuid references team2.profiles(id) on delete set null,
  created_at    timestamptz not null default now()
);

create index if not exists idx_team2_whatsapp_log_time on team2.whatsapp_log(created_at desc);

alter table team2.whatsapp_log enable row level security;

drop policy if exists whatsapp_log_admin_read on team2.whatsapp_log;
create policy whatsapp_log_admin_read on team2.whatsapp_log for select to authenticated
  using (team2.is_admin());

grant select on team2.whatsapp_log to authenticated;

-- The two approved templates live in team2.integrations (provider = 'whatsapp'),
-- config->'templates'->'message' and ->'otp'. The access key is in secret->'access_token'
-- and is set by hand, never written into this repo.

notify pgrst, 'reload schema';
