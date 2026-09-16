-- Team2 — SMS send log (SMV SMS gateway). Applied as migration `team2_sms_log`.
-- Written only by the team2-sms edge function (service role); admins can read it.
create table if not exists team2.sms_log (
  id             bigserial primary key,
  template       text not null,
  to_number      text not null,
  message        text not null,
  status         text not null check (status in ('sent', 'failed')),
  error          text,
  provider_reply text,
  sent_by        uuid references team2.profiles(id) on delete set null,
  created_at     timestamptz not null default now()
);

create index if not exists idx_team2_sms_log_time on team2.sms_log(created_at desc);

alter table team2.sms_log enable row level security;

drop policy if exists sms_log_admin_read on team2.sms_log;
create policy sms_log_admin_read on team2.sms_log for select to authenticated
  using (team2.is_admin());

grant select on team2.sms_log to authenticated;

-- SMS settings live in team2.integrations (provider = 'sms'): api_url, sender_id,
-- dlt_entity_id, route and config->'templates'->'otp' (DLT template id + exact body).
-- The authentic-key is in secret->'api_key', set by hand, never written into this repo.

notify pgrst, 'reload schema';
