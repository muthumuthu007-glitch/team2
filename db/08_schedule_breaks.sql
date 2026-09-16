-- Team2 — Schedules (the Shift master, relabelled "Schedule" in the app).
-- Applied as migration `team2_schedule_breaks_and_permission`.
--
-- The table keeps the name `shifts`: profiles.shift_id, team2.sync_attendance_day()
-- and role_permissions.menu_id = 'shifts' all key on it.

alter table team2.shifts
  add column if not exists tea1_from  time,
  add column if not exists tea1_to    time,
  add column if not exists tea1_min   integer not null default 0,
  add column if not exists tea2_from  time,
  add column if not exists tea2_to    time,
  add column if not exists tea2_min   integer not null default 0,
  add column if not exists tea3_from  time,
  add column if not exists tea3_to    time,
  add column if not exists tea3_min   integer not null default 0,
  add column if not exists lunch_from time,
  add column if not exists lunch_to   time,
  add column if not exists lunch_min  integer not null default 0,
  -- Permission = short leave. Allowance is quoted per 26-day month.
  add column if not exists permission_hours numeric(4,1) not null default 3;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'shifts_break_minutes_chk') then
    alter table team2.shifts add constraint shifts_break_minutes_chk
      check (tea1_min between 0 and 240 and tea2_min between 0 and 240
         and tea3_min between 0 and 240 and lunch_min between 0 and 480);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'shifts_permission_hours_chk') then
    alter table team2.shifts add constraint shifts_permission_hours_chk
      check (permission_hours >= 0 and permission_hours <= 100);
  end if;
end $$;

notify pgrst, 'reload schema';
