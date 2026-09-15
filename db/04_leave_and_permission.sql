-- Team2 — leave (full/half day) and permission (short leave inside a day).
-- Applied as migration `team2_leave_and_permission`.

create sequence if not exists team2.leave_type_code_seq start 1;

create table if not exists team2.leave_types (
  id              uuid primary key default gen_random_uuid(),
  leave_type_code text unique not null
                  default 'LVT-' || lpad(nextval('team2.leave_type_code_seq')::text, 3, '0'),
  name            text not null,
  short_name      text,
  is_paid         boolean not null default true,
  annual_quota    numeric(5,1) not null default 0,
  carry_forward   boolean not null default false,
  max_carry       numeric(5,1) not null default 0,
  allow_half_day  boolean not null default true,
  min_notice_days integer not null default 0,
  max_consecutive integer,
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  created_by      uuid references team2.profiles(id) on delete set null,
  updated_at      timestamptz not null default now()
);

-- Opening + accrued - used, per employee per leave type per calendar year.
create table if not exists team2.leave_balances (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references team2.profiles(id) on delete cascade,
  leave_type_id uuid not null references team2.leave_types(id) on delete cascade,
  year          integer not null,
  opening       numeric(5,1) not null default 0,
  accrued       numeric(5,1) not null default 0,
  used          numeric(5,1) not null default 0,
  balance       numeric(6,1) generated always as (opening + accrued - used) stored,
  updated_at    timestamptz not null default now(),
  unique (user_id, leave_type_id, year)
);

create index if not exists idx_team2_leave_balances_user on team2.leave_balances(user_id, year);

create table if not exists team2.leave_requests (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references team2.profiles(id) on delete cascade,
  leave_type_id uuid not null references team2.leave_types(id) on delete restrict,
  from_date     date not null,
  to_date       date not null,
  from_half     boolean not null default false,   -- start on the second half of from_date
  to_half       boolean not null default false,   -- end at the first half of to_date
  days          numeric(5,1) not null default 1,
  reason        text not null,
  contact_no    text,
  status        text not null default 'pending'
                check (status in ('pending','approved','rejected','cancelled')),
  approver_id   uuid references team2.profiles(id) on delete set null,
  acted_at      timestamptz,
  approver_note text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (to_date >= from_date)
);

create index if not exists idx_team2_leave_requests_user on team2.leave_requests(user_id, from_date desc);
create index if not exists idx_team2_leave_requests_status on team2.leave_requests(status);

-- "Permission" = short leave measured in minutes, always inside one day.
create table if not exists team2.permission_requests (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references team2.profiles(id) on delete cascade,
  on_date       date not null,
  from_time     time not null,
  to_time       time not null,
  minutes       integer generated always as
                (((extract(epoch from (to_time - from_time)) / 60))::integer) stored,
  reason        text not null,
  status        text not null default 'pending'
                check (status in ('pending','approved','rejected','cancelled')),
  approver_id   uuid references team2.profiles(id) on delete set null,
  acted_at      timestamptz,
  approver_note text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (to_time > from_time)
);

create index if not exists idx_team2_permission_requests_user
  on team2.permission_requests(user_id, on_date desc);
create index if not exists idx_team2_permission_requests_status
  on team2.permission_requests(status);

do $$
declare t text;
begin
  foreach t in array array['leave_types','leave_balances','leave_requests','permission_requests'] loop
    execute format('drop trigger if exists %s_touch_updated_at on team2.%I', t, t);
    execute format('create trigger %s_touch_updated_at before update on team2.%I
                    for each row execute function team2.touch_updated_at()', t, t);
    execute format('alter table team2.%I enable row level security', t);
  end loop;
end $$;

-- Leave types are a master.
drop policy if exists leave_types_select on team2.leave_types;
create policy leave_types_select on team2.leave_types for select to authenticated
  using (team2.can_view('leave_types', created_by, null));

drop policy if exists leave_types_insert on team2.leave_types;
create policy leave_types_insert on team2.leave_types for insert to authenticated
  with check (team2.can_edit('leave_types', auth.uid(), null));

drop policy if exists leave_types_update on team2.leave_types;
create policy leave_types_update on team2.leave_types for update to authenticated
  using (team2.can_edit('leave_types', created_by, null))
  with check (team2.can_edit('leave_types', created_by, null));

drop policy if exists leave_types_delete on team2.leave_types;
create policy leave_types_delete on team2.leave_types for delete to authenticated
  using (team2.is_manager() and team2.can_edit('leave_types', created_by, null));

-- Balances: yours to read, admin's to set.
drop policy if exists leave_balances_select on team2.leave_balances;
create policy leave_balances_select on team2.leave_balances for select to authenticated
  using (team2.can_view_record('leave_requests', user_id));

drop policy if exists leave_balances_write on team2.leave_balances;
create policy leave_balances_write on team2.leave_balances for all to authenticated
  using (team2.is_admin()) with check (team2.is_admin());

-- Requests: raise your own, edit while pending, cancel. Approvers act on their team.
do $$
declare t text;
begin
  foreach t in array array['leave_requests','permission_requests'] loop
    execute format('drop policy if exists %s_select on team2.%I', t, t);
    execute format('create policy %s_select on team2.%I for select to authenticated
                    using (team2.can_view_record(%L, user_id))', t, t, t);

    execute format('drop policy if exists %s_insert on team2.%I', t, t);
    execute format('create policy %s_insert on team2.%I for insert to authenticated
                    with check (user_id = auth.uid() or team2.is_admin())', t, t);

    execute format('drop policy if exists %s_update on team2.%I', t, t);
    execute format('create policy %s_update on team2.%I for update to authenticated
                    using ((user_id = auth.uid() and status = ''pending'')
                           or team2.can_approve_for(user_id))
                    with check ((user_id = auth.uid() and status in (''pending'',''cancelled''))
                           or team2.can_approve_for(user_id))', t, t);

    execute format('drop policy if exists %s_delete on team2.%I', t, t);
    execute format('create policy %s_delete on team2.%I for delete to authenticated
                    using ((user_id = auth.uid() and status = ''pending'') or team2.is_admin())', t, t);
  end loop;
end $$;
