-- Team2 — attendance. A punch is the raw event; team2.attendance is the derived day row.
-- Applied as migration `team2_attendance_punches_and_regularisations`.

-- The business day is IST. Change here, not in twelve places.
create or replace function team2.biz_date(ts timestamptz) returns date
language sql stable set search_path = team2, public as $$
  select (ts at time zone 'Asia/Kolkata')::date
$$;

-- One row per employee per day. Maintained by trigger from the punches below;
-- status may be overridden by an admin (leave / holiday / on duty) and is not
-- overwritten once set.
create table if not exists team2.attendance (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references team2.profiles(id) on delete cascade,
  work_date         date not null,
  shift_id          uuid references team2.shifts(id) on delete set null,
  status            text not null default 'absent'
                    check (status in ('present','absent','half_day','leave','permission',
                                      'holiday','week_off','on_duty','wfh')),
  first_in_at       timestamptz,
  last_out_at       timestamptz,
  worked_minutes    integer,
  late_minutes      integer,
  early_out_minutes integer,
  ot_minutes        integer,
  remarks           text,
  source            text not null default 'punch'
                    check (source in ('punch','manual','import','auto')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (user_id, work_date)
);

create index if not exists idx_team2_attendance_date on team2.attendance(work_date);
create index if not exists idx_team2_attendance_user_date on team2.attendance(user_id, work_date desc);

-- Raw punch events. Never edited — a wrong punch is fixed by a regularisation.
create table if not exists team2.attendance_punches (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references team2.profiles(id) on delete cascade,
  punched_at      timestamptz not null default now(),
  direction       text not null check (direction in ('in','out')),
  lat             double precision,
  lng             double precision,
  accuracy_m      double precision,
  address         text,                 -- reverse-geocoded via Google Geocoding
  location_id     uuid references team2.locations(id) on delete set null,
  within_geofence boolean,
  distance_m      double precision,     -- metres from the mapped location
  selfie_url      text,
  device          text,
  source          text not null default 'mobile'
                  check (source in ('mobile','web','kiosk','manual')),
  remarks         text,
  created_by      uuid references team2.profiles(id) on delete set null,
  created_at      timestamptz not null default now()
);

create index if not exists idx_team2_punches_user_time
  on team2.attendance_punches(user_id, punched_at desc);

-- Roll the day's punches up into team2.attendance.
create or replace function team2.sync_attendance_day() returns trigger
language plpgsql security definer set search_path = team2, public as $$
declare
  d     date;
  f     timestamptz;
  l     timestamptz;
  mins  integer;
  sh    team2.shifts%rowtype;
  late  integer;
  early integer;
  ot    integer;
  st    text;
begin
  d := team2.biz_date(new.punched_at);

  select min(punched_at) filter (where direction = 'in'),
         max(punched_at) filter (where direction = 'out')
    into f, l
    from team2.attendance_punches
   where user_id = new.user_id
     and team2.biz_date(punched_at) = d;

  if f is not null and l is not null and l > f then
    mins := floor(extract(epoch from (l - f)) / 60)::integer;
  end if;

  select s.* into sh
    from team2.profiles p
    join team2.shifts s on s.id = p.shift_id
   where p.id = new.user_id;

  if sh.id is not null then
    if f is not null then
      late := greatest(0, floor(extract(epoch from
                ((f at time zone 'Asia/Kolkata') - (d + sh.start_time))) / 60)::integer
                - sh.grace_in_min);
    end if;
    if l is not null then
      early := greatest(0, floor(extract(epoch from
                 ((d + sh.end_time) - (l at time zone 'Asia/Kolkata'))) / 60)::integer
                 - sh.grace_out_min);
      ot    := greatest(0, floor(extract(epoch from
                 ((l at time zone 'Asia/Kolkata') - (d + sh.end_time))) / 60)::integer
                 - sh.grace_out_min);
    end if;
    if mins is not null and mins < sh.full_day_min and mins >= sh.half_day_min then
      st := 'half_day';
    end if;
  end if;

  insert into team2.attendance (user_id, work_date, shift_id, status, first_in_at, last_out_at,
                                worked_minutes, late_minutes, early_out_minutes, ot_minutes, source)
  values (new.user_id, d, sh.id, coalesce(st, 'present'), f, l, mins, late, early, ot, 'punch')
  on conflict (user_id, work_date) do update set
    shift_id          = coalesce(attendance.shift_id, excluded.shift_id),
    first_in_at       = excluded.first_in_at,
    last_out_at       = excluded.last_out_at,
    worked_minutes    = excluded.worked_minutes,
    late_minutes      = excluded.late_minutes,
    early_out_minutes = excluded.early_out_minutes,
    ot_minutes        = excluded.ot_minutes,
    updated_at        = now();

  return new;
end $$;

drop trigger if exists punches_sync_attendance on team2.attendance_punches;
create trigger punches_sync_attendance after insert on team2.attendance_punches
  for each row execute function team2.sync_attendance_day();

-- Attendance correction request (missed punch, wrong time).
create table if not exists team2.regularisations (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references team2.profiles(id) on delete cascade,
  work_date     date not null,
  requested_in  timestamptz,
  requested_out timestamptz,
  reason        text not null,
  status        text not null default 'pending'
                check (status in ('pending','approved','rejected','cancelled')),
  approver_id   uuid references team2.profiles(id) on delete set null,
  acted_at      timestamptz,
  approver_note text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists idx_team2_regularisations_user on team2.regularisations(user_id, work_date desc);
create index if not exists idx_team2_regularisations_status on team2.regularisations(status);

drop trigger if exists attendance_touch_updated_at on team2.attendance;
create trigger attendance_touch_updated_at before update on team2.attendance
  for each row execute function team2.touch_updated_at();

drop trigger if exists regularisations_touch_updated_at on team2.regularisations;
create trigger regularisations_touch_updated_at before update on team2.regularisations
  for each row execute function team2.touch_updated_at();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table team2.attendance          enable row level security;
alter table team2.attendance_punches  enable row level security;
alter table team2.regularisations     enable row level security;

drop policy if exists attendance_select on team2.attendance;
create policy attendance_select on team2.attendance for select to authenticated
  using (team2.can_view_record('attendance', user_id));

drop policy if exists attendance_insert on team2.attendance;
create policy attendance_insert on team2.attendance for insert to authenticated
  with check (team2.can_edit_record('attendance', user_id));

drop policy if exists attendance_update on team2.attendance;
create policy attendance_update on team2.attendance for update to authenticated
  using (team2.can_edit_record('attendance', user_id))
  with check (team2.can_edit_record('attendance', user_id));

drop policy if exists attendance_delete on team2.attendance;
create policy attendance_delete on team2.attendance for delete to authenticated
  using (team2.is_admin());

-- Punches: you may record your own; only an admin may touch one afterwards.
drop policy if exists punches_select on team2.attendance_punches;
create policy punches_select on team2.attendance_punches for select to authenticated
  using (team2.can_view_record('attendance', user_id));

drop policy if exists punches_insert on team2.attendance_punches;
create policy punches_insert on team2.attendance_punches for insert to authenticated
  with check (user_id = auth.uid() or team2.is_admin());

drop policy if exists punches_update on team2.attendance_punches;
create policy punches_update on team2.attendance_punches for update to authenticated
  using (team2.is_admin()) with check (team2.is_admin());

drop policy if exists punches_delete on team2.attendance_punches;
create policy punches_delete on team2.attendance_punches for delete to authenticated
  using (team2.is_admin());

-- Requests: raise your own, edit it while pending, cancel it. Approvers act on their team.
drop policy if exists regularisations_select on team2.regularisations;
create policy regularisations_select on team2.regularisations for select to authenticated
  using (team2.can_view_record('regularisations', user_id));

drop policy if exists regularisations_insert on team2.regularisations;
create policy regularisations_insert on team2.regularisations for insert to authenticated
  with check (user_id = auth.uid() or team2.is_admin());

drop policy if exists regularisations_update on team2.regularisations;
create policy regularisations_update on team2.regularisations for update to authenticated
  using ((user_id = auth.uid() and status = 'pending') or team2.can_approve_for(user_id))
  with check ((user_id = auth.uid() and status in ('pending','cancelled'))
              or team2.can_approve_for(user_id));

drop policy if exists regularisations_delete on team2.regularisations;
create policy regularisations_delete on team2.regularisations for delete to authenticated
  using ((user_id = auth.uid() and status = 'pending') or team2.is_admin());
