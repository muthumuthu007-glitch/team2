-- Team2 — visits, GPS tracking and travel. Google Maps supplies the address,
-- the place id and the road distance; the raw lat/lng is always stored too.
-- Applied as migration `team2_visits_tracking_and_settings`.

-- Straight-line metres between two points. Used for geofence checks and as the
-- fallback when no Google road distance is available.
create or replace function team2.distance_m(
  lat1 double precision, lng1 double precision,
  lat2 double precision, lng2 double precision
) returns double precision
language sql immutable as $$
  select case
    when lat1 is null or lng1 is null or lat2 is null or lng2 is null then null
    else 6371000 * 2 * asin(sqrt(
           power(sin(radians(lat2 - lat1) / 2), 2) +
           cos(radians(lat1)) * cos(radians(lat2)) *
           power(sin(radians(lng2 - lng1) / 2), 2)))
  end
$$;

create sequence if not exists team2.party_code_seq   start 1;
create sequence if not exists team2.purpose_code_seq start 1;
create sequence if not exists team2.visit_no_seq     start 1;

-- Who you visit: customer, prospect, dealer, vendor or a site.
create table if not exists team2.parties (
  id              uuid primary key default gen_random_uuid(),
  party_code      text unique not null
                  default 'PTY-' || lpad(nextval('team2.party_code_seq')::text, 4, '0'),
  name            text not null,
  party_type      text not null default 'customer'
                  check (party_type in ('customer','prospect','dealer','vendor','site','other')),
  contact_person  text,
  phone           text,
  email           text,
  address         text,
  city            text,
  state           text,
  pincode         text,
  lat             double precision,
  lng             double precision,
  google_place_id text,                                            -- from Places autocomplete
  location_id     uuid references team2.locations(id) on delete set null,
  owner_id        uuid references team2.profiles(id) on delete set null,   -- assigned staff
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  created_by      uuid references team2.profiles(id) on delete set null,
  updated_at      timestamptz not null default now()
);

create index if not exists idx_team2_parties_owner on team2.parties(owner_id);
create index if not exists idx_team2_parties_name  on team2.parties(name);

create table if not exists team2.visit_purposes (
  id           uuid primary key default gen_random_uuid(),
  purpose_code text unique not null
               default 'VPR-' || lpad(nextval('team2.purpose_code_seq')::text, 3, '0'),
  name         text not null,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  created_by   uuid references team2.profiles(id) on delete set null,
  updated_at   timestamptz not null default now()
);

-- A visit is planned, then checked in and out on site.
create table if not exists team2.visits (
  id                   uuid primary key default gen_random_uuid(),
  visit_no             text unique not null
                       default 'V-' || lpad(nextval('team2.visit_no_seq')::text, 6, '0'),
  user_id              uuid not null references team2.profiles(id) on delete cascade,
  party_id             uuid references team2.parties(id) on delete set null,
  purpose_id           uuid references team2.visit_purposes(id) on delete set null,
  title                text,
  planned_date         date not null default (now() at time zone 'Asia/Kolkata')::date,
  planned_time         time,
  status               text not null default 'planned'
                       check (status in ('planned','checked_in','completed','cancelled','missed')),

  check_in_at          timestamptz,
  check_in_lat         double precision,
  check_in_lng         double precision,
  check_in_accuracy_m  double precision,
  check_in_address     text,
  check_in_distance_m  double precision,   -- from the party's mapped point
  check_out_at         timestamptz,
  check_out_lat        double precision,
  check_out_lng        double precision,
  check_out_address    text,
  duration_minutes     integer generated always as (
                         case when check_in_at is not null and check_out_at is not null
                              then (extract(epoch from (check_out_at - check_in_at)) / 60)::integer
                         end) stored,

  notes                text,
  outcome              text,
  next_action          text,
  next_action_date     date,
  created_by           uuid references team2.profiles(id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create index if not exists idx_team2_visits_user_date on team2.visits(user_id, planned_date desc);
create index if not exists idx_team2_visits_party  on team2.visits(party_id);
create index if not exists idx_team2_visits_status on team2.visits(status);

create table if not exists team2.visit_photos (
  id         uuid primary key default gen_random_uuid(),
  visit_id   uuid not null references team2.visits(id) on delete cascade,
  url        text not null,
  caption    text,
  taken_at   timestamptz not null default now(),
  lat        double precision,
  lng        double precision,
  created_by uuid references team2.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_team2_visit_photos_visit on team2.visit_photos(visit_id);

-- Breadcrumb trail. High volume — one row every tracking interval while on duty.
create table if not exists team2.visit_tracks (
  id         bigserial primary key,
  user_id    uuid not null references team2.profiles(id) on delete cascade,
  tracked_at timestamptz not null default now(),
  lat        double precision not null,
  lng        double precision not null,
  accuracy_m double precision,
  speed_kmph double precision,
  heading    double precision,
  battery_pct integer,
  visit_id   uuid references team2.visits(id) on delete set null,
  trip_id    uuid,
  created_at timestamptz not null default now()
);

create index if not exists idx_team2_tracks_user_time on team2.visit_tracks(user_id, tracked_at desc);
create index if not exists idx_team2_tracks_visit on team2.visit_tracks(visit_id);

-- One travel summary per employee per day.
create table if not exists team2.trips (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references team2.profiles(id) on delete cascade,
  trip_date         date not null,
  start_at          timestamptz,
  end_at            timestamptz,
  start_lat         double precision,
  start_lng         double precision,
  start_address     text,
  end_lat           double precision,
  end_lng           double precision,
  end_address       text,
  track_distance_km numeric(8,2),   -- summed from visit_tracks
  google_distance_km numeric(8,2),  -- Google Distance Matrix / Routes
  claimed_km        numeric(8,2),   -- what the employee claims
  mode              text check (mode in ('bike','car','bus','train','taxi','walk','other')),
  notes             text,
  status            text not null default 'open'
                    check (status in ('open','submitted','approved','rejected')),
  approver_id       uuid references team2.profiles(id) on delete set null,
  acted_at          timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (user_id, trip_date)
);

create index if not exists idx_team2_trips_date on team2.trips(trip_date desc);

alter table team2.visit_tracks
  add constraint visit_tracks_trip_fk foreign key (trip_id)
  references team2.trips(id) on delete set null;

-- App-wide switches (tracking interval, geofence default, monthly permission cap …).
create table if not exists team2.app_settings (
  key         text primary key,
  value       jsonb not null,
  description text,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references team2.profiles(id) on delete set null
);

insert into team2.app_settings (key, value, description) values
  ('track_interval_seconds', '180'::jsonb, 'How often the app records a GPS breadcrumb while on duty'),
  ('geofence_default_m',     '200'::jsonb, 'Default punch radius when a location has none'),
  ('permission_max_per_month','2'::jsonb,  'Permission requests allowed per employee per month'),
  ('permission_max_minutes', '120'::jsonb, 'Longest single permission, in minutes'),
  ('selfie_on_punch',        'true'::jsonb,'Require a selfie with every punch'),
  ('week_start',             '"monday"'::jsonb, 'First day of the week in reports')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Triggers + RLS
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['parties','visit_purposes','visits','trips','app_settings'] loop
    execute format('drop trigger if exists %s_touch_updated_at on team2.%I', t, t);
    execute format('create trigger %s_touch_updated_at before update on team2.%I
                    for each row execute function team2.touch_updated_at()', t, t);
  end loop;

  foreach t in array array['parties','visit_purposes','visits','visit_photos',
                           'visit_tracks','trips','app_settings'] loop
    execute format('alter table team2.%I enable row level security', t);
  end loop;

  -- parties and visit_purposes are masters
  foreach t in array array['parties','visit_purposes'] loop
    execute format('drop policy if exists %s_select on team2.%I', t, t);
    execute format('create policy %s_select on team2.%I for select to authenticated
                    using (team2.can_view(%L, created_by, null))', t, t, t);

    execute format('drop policy if exists %s_insert on team2.%I', t, t);
    execute format('create policy %s_insert on team2.%I for insert to authenticated
                    with check (team2.can_edit(%L, auth.uid(), null))', t, t, t);

    execute format('drop policy if exists %s_update on team2.%I', t, t);
    execute format('create policy %s_update on team2.%I for update to authenticated
                    using (team2.can_edit(%L, created_by, null))
                    with check (team2.can_edit(%L, created_by, null))', t, t, t, t);

    execute format('drop policy if exists %s_delete on team2.%I', t, t);
    execute format('create policy %s_delete on team2.%I for delete to authenticated
                    using (team2.is_manager() and team2.can_edit(%L, created_by, null))', t, t, t);
  end loop;
end $$;

drop policy if exists visits_select on team2.visits;
create policy visits_select on team2.visits for select to authenticated
  using (team2.can_view_record('visits', user_id));

drop policy if exists visits_insert on team2.visits;
create policy visits_insert on team2.visits for insert to authenticated
  with check (user_id = auth.uid() or team2.can_edit_record('visits', user_id));

drop policy if exists visits_update on team2.visits;
create policy visits_update on team2.visits for update to authenticated
  using (user_id = auth.uid() or team2.can_edit_record('visits', user_id))
  with check (user_id = auth.uid() or team2.can_edit_record('visits', user_id));

drop policy if exists visits_delete on team2.visits;
create policy visits_delete on team2.visits for delete to authenticated
  using ((user_id = auth.uid() and status = 'planned') or team2.is_admin());

drop policy if exists visit_photos_select on team2.visit_photos;
create policy visit_photos_select on team2.visit_photos for select to authenticated
  using (exists (select 1 from team2.visits v
                  where v.id = visit_id and team2.can_view_record('visits', v.user_id)));

drop policy if exists visit_photos_write on team2.visit_photos;
create policy visit_photos_write on team2.visit_photos for all to authenticated
  using (exists (select 1 from team2.visits v
                  where v.id = visit_id and (v.user_id = auth.uid() or team2.is_admin())))
  with check (exists (select 1 from team2.visits v
                  where v.id = visit_id and (v.user_id = auth.uid() or team2.is_admin())));

-- Tracks are append-only evidence: you write your own, nobody edits them.
drop policy if exists visit_tracks_select on team2.visit_tracks;
create policy visit_tracks_select on team2.visit_tracks for select to authenticated
  using (team2.can_view_record('visit_tracks', user_id));

drop policy if exists visit_tracks_insert on team2.visit_tracks;
create policy visit_tracks_insert on team2.visit_tracks for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists visit_tracks_delete on team2.visit_tracks;
create policy visit_tracks_delete on team2.visit_tracks for delete to authenticated
  using (team2.is_admin());

drop policy if exists trips_select on team2.trips;
create policy trips_select on team2.trips for select to authenticated
  using (team2.can_view_record('trips', user_id));

drop policy if exists trips_insert on team2.trips;
create policy trips_insert on team2.trips for insert to authenticated
  with check (user_id = auth.uid() or team2.is_admin());

drop policy if exists trips_update on team2.trips;
create policy trips_update on team2.trips for update to authenticated
  using ((user_id = auth.uid() and status in ('open','rejected')) or team2.can_approve_for(user_id))
  with check ((user_id = auth.uid() and status in ('open','submitted'))
              or team2.can_approve_for(user_id));

drop policy if exists trips_delete on team2.trips;
create policy trips_delete on team2.trips for delete to authenticated
  using (team2.is_admin());

drop policy if exists app_settings_select on team2.app_settings;
create policy app_settings_select on team2.app_settings for select to authenticated using (true);

drop policy if exists app_settings_write on team2.app_settings;
create policy app_settings_write on team2.app_settings for all to authenticated
  using (team2.is_admin()) with check (team2.is_admin());

grant select, insert, update, delete on all tables in schema team2 to authenticated;
grant usage, select on all sequences in schema team2 to authenticated;
grant execute on all functions in schema team2 to authenticated;
