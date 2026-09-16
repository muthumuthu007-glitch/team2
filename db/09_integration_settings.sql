-- Team2 — integration settings for WhatsApp, SMS and email reports.
-- Applied as migration `team2_integration_settings`.
--
-- Why a separate table and not team2.app_settings: app_settings is readable by EVERY
-- signed-in user (the app needs some of it in the browser). Access tokens, API keys and
-- SMTP passwords must not be. This table is admin-only for both read and write.
--
-- Nothing here sends anything: a browser cannot hold a sending secret safely. Actual
-- sending needs an edge function that keeps the token server-side.

create table if not exists team2.integrations (
  provider   text primary key check (provider in ('whatsapp', 'sms', 'email')),
  config     jsonb   not null default '{}'::jsonb,   -- non-secret: host, sender id, recipients…
  secret     jsonb   not null default '{}'::jsonb,   -- tokens, api keys, passwords
  enabled    boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references team2.profiles(id) on delete set null
);

alter table team2.integrations enable row level security;

drop policy if exists integrations_admin_all on team2.integrations;
create policy integrations_admin_all on team2.integrations for all to authenticated
  using (team2.is_admin()) with check (team2.is_admin());

drop trigger if exists integrations_touch_updated_at on team2.integrations;
create trigger integrations_touch_updated_at before update on team2.integrations
  for each row execute function team2.touch_updated_at();

grant select, insert, update, delete on team2.integrations to authenticated;

insert into team2.integrations (provider) values ('whatsapp'), ('sms'), ('email')
on conflict (provider) do nothing;

-- The Google Maps browser key lives in app_settings instead: the browser has to read it
-- to load the map at all, so it cannot be admin-only. It is a publishable key — protect
-- it with an HTTP referrer restriction in Google Cloud, not by hiding it.
insert into team2.app_settings (key, value, description) values
  ('google_maps_key', '""'::jsonb,
   'Google Maps browser key. Restrict it by HTTP referrer; it is visible to anyone using the app.')
on conflict (key) do nothing;

notify pgrst, 'reload schema';
