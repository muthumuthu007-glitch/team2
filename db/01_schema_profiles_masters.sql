-- Team2 — attendance / leave / permission / visit app.
-- Applied to project thmszlxepqkrcqavlilq as migration `team2_init_schema_profiles_and_masters`.
-- Kept here as the source of truth.
--
-- Own schema so it never collides with mono, muthus or asset.

create schema if not exists team2;
grant usage on schema team2 to anon, authenticated, service_role;

create or replace function team2.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- User master. Username is the mobile number, mapped to <username>@team2.app.
-- ---------------------------------------------------------------------------
create table if not exists team2.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  username     text unique not null,
  name         text not null,
  role         text not null default 'staff'
               check (role in ('superadmin','admin','manager','staff')),
  emp_code     text unique,
  phone        text,
  email        text,
  active       boolean not null default true,
  date_of_join date,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

drop trigger if exists profiles_touch_updated_at on team2.profiles;
create trigger profiles_touch_updated_at before update on team2.profiles
  for each row execute function team2.touch_updated_at();

-- Role helpers (security definer, so policies on profiles do not recurse).
create or replace function team2.my_role() returns text
language sql stable security definer set search_path = team2, public as $$
  select role from team2.profiles where id = auth.uid()
$$;

create or replace function team2.is_admin() returns boolean
language sql stable security definer set search_path = team2, public as $$
  select coalesce((select role in ('superadmin','admin') from team2.profiles where id = auth.uid()), false)
$$;

create or replace function team2.is_manager() returns boolean
language sql stable security definer set search_path = team2, public as $$
  select coalesce((select role in ('superadmin','admin','manager') from team2.profiles where id = auth.uid()), false)
$$;

alter table team2.profiles enable row level security;

drop policy if exists profiles_select on team2.profiles;
create policy profiles_select on team2.profiles for select to authenticated using (true);

drop policy if exists profiles_admin_write on team2.profiles;
create policy profiles_admin_write on team2.profiles for all to authenticated
  using (team2.is_admin()) with check (team2.is_admin());

-- ---------------------------------------------------------------------------
-- Masters
-- ---------------------------------------------------------------------------
create sequence if not exists team2.location_code_seq    start 1;
create sequence if not exists team2.department_code_seq  start 1;
create sequence if not exists team2.designation_code_seq start 1;
create sequence if not exists team2.role_code_seq        start 1;
create sequence if not exists team2.shift_code_seq       start 1;

-- Office / site. lat+lng+radius drive attendance geofencing.
create table if not exists team2.locations (
  id            uuid primary key default gen_random_uuid(),
  location_code text unique not null
                default 'LOC-' || lpad(nextval('team2.location_code_seq')::text, 3, '0'),
  name          text not null,
  address       text,
  city          text,
  state         text,
  pincode       text,
  lat           double precision,
  lng           double precision,
  geofence_m    integer not null default 200,   -- allowed punch radius, metres
  google_place_id text,
  active        boolean not null default true,
  created_at    timestamptz not null default now(),
  created_by    uuid references team2.profiles(id) on delete set null,
  updated_at    timestamptz not null default now()
);

create table if not exists team2.departments (
  id              uuid primary key default gen_random_uuid(),
  department_code text unique not null
                  default 'DEP-' || lpad(nextval('team2.department_code_seq')::text, 3, '0'),
  name            text not null,
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  created_by      uuid references team2.profiles(id) on delete set null,
  updated_at      timestamptz not null default now()
);

create table if not exists team2.designations (
  id               uuid primary key default gen_random_uuid(),
  designation_code text unique not null
                   default 'DSG-' || lpad(nextval('team2.designation_code_seq')::text, 3, '0'),
  name             text not null,
  active           boolean not null default true,
  created_at       timestamptz not null default now(),
  created_by       uuid references team2.profiles(id) on delete set null,
  updated_at       timestamptz not null default now()
);

create table if not exists team2.roles (
  id          uuid primary key default gen_random_uuid(),
  role_code   text unique not null
              default 'ROL-' || lpad(nextval('team2.role_code_seq')::text, 3, '0'),
  name        text not null,
  description text,
  is_admin    boolean not null default false,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  created_by  uuid references team2.profiles(id) on delete set null,
  updated_at  timestamptz not null default now()
);

-- week_offs: ISO day numbers, 0 = Sunday … 6 = Saturday.
create table if not exists team2.shifts (
  id             uuid primary key default gen_random_uuid(),
  shift_code     text unique not null
                 default 'SHF-' || lpad(nextval('team2.shift_code_seq')::text, 3, '0'),
  name           text not null,
  start_time     time not null default '09:30',
  end_time       time not null default '18:30',
  grace_in_min   integer not null default 10,
  grace_out_min  integer not null default 10,
  half_day_min   integer not null default 240,
  full_day_min   integer not null default 480,
  night_shift    boolean not null default false,
  week_offs      integer[] not null default '{0}',
  active         boolean not null default true,
  created_at     timestamptz not null default now(),
  created_by     uuid references team2.profiles(id) on delete set null,
  updated_at     timestamptz not null default now()
);

-- location_id null = applies to every location.
create table if not exists team2.holidays (
  id           uuid primary key default gen_random_uuid(),
  holiday_date date not null,
  name         text not null,
  location_id  uuid references team2.locations(id) on delete cascade,
  optional     boolean not null default false,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  created_by   uuid references team2.profiles(id) on delete set null,
  updated_at   timestamptz not null default now()
);

create unique index if not exists uq_team2_holiday
  on team2.holidays (holiday_date, coalesce(location_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- Link a user to their org placement and reporting line.
alter table team2.profiles
  add column if not exists role_id        uuid references team2.roles(id)        on delete set null,
  add column if not exists location_id    uuid references team2.locations(id)    on delete set null,
  add column if not exists department_id  uuid references team2.departments(id)  on delete set null,
  add column if not exists designation_id uuid references team2.designations(id) on delete set null,
  add column if not exists shift_id       uuid references team2.shifts(id)       on delete set null,
  add column if not exists reporting_to   uuid references team2.profiles(id)     on delete set null;

create index if not exists idx_team2_profiles_reporting on team2.profiles(reporting_to);
create index if not exists idx_team2_profiles_location  on team2.profiles(location_id);

-- ---------------------------------------------------------------------------
-- Role permission matrix — one row per (role, menu).
--   none | view_own | edit_own | view_all | edit_all
-- menu_id matches the id in the app's MENUS array; for masters that equals the table name.
-- ---------------------------------------------------------------------------
create table if not exists team2.role_permissions (
  id         uuid primary key default gen_random_uuid(),
  role_id    uuid not null references team2.roles(id) on delete cascade,
  menu_id    text not null,
  access     text not null default 'none'
             check (access in ('none','view_own','edit_own','view_all','edit_all')),
  updated_at timestamptz not null default now(),
  updated_by uuid references team2.profiles(id) on delete set null,
  unique (role_id, menu_id)
);

create index if not exists idx_team2_role_permissions_role on team2.role_permissions(role_id);

alter table team2.role_permissions enable row level security;

drop policy if exists role_permissions_select on team2.role_permissions;
create policy role_permissions_select on team2.role_permissions for select to authenticated using (true);

drop policy if exists role_permissions_write on team2.role_permissions;
create policy role_permissions_write on team2.role_permissions for all to authenticated
  using (team2.is_admin()) with check (team2.is_admin());

-- ---------------------------------------------------------------------------
-- Grants — anything added later inherits these too.
-- ---------------------------------------------------------------------------
grant select, insert, update, delete on all tables in schema team2 to authenticated;
grant usage, select on all sequences in schema team2 to authenticated;
grant execute on all functions in schema team2 to authenticated;

alter default privileges in schema team2 grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema team2 grant usage, select on sequences to authenticated;
alter default privileges in schema team2 grant execute on functions to authenticated;
