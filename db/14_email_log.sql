-- Team2 — email send log. Applied as migration `team2_email_log`.
-- Written only by the team2-email edge function; admins can read it.
create table if not exists team2.email_log (
  id          bigserial primary key,
  kind        text not null default 'test',
  to_address  text not null,
  subject     text not null,
  status      text not null check (status in ('sent', 'failed')),
  error       text,
  sent_by     uuid references team2.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);

create index if not exists idx_team2_email_log_time on team2.email_log(created_at desc);

alter table team2.email_log enable row level security;

drop policy if exists email_log_admin_read on team2.email_log;
create policy email_log_admin_read on team2.email_log for select to authenticated
  using (team2.is_admin());

grant select on team2.email_log to authenticated;
grant select, insert, update, delete on team2.email_log to service_role;
grant usage, select on sequence team2.email_log_id_seq to service_role;

notify pgrst, 'reload schema';
