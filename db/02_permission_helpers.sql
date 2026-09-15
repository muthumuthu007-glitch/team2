-- Team2 — the helpers every RLS policy calls, then the master-table policies.
-- Applied as migration `team2_permission_helpers_and_master_rls`.

create or replace function team2.my_location_id() returns uuid
language sql stable security definer set search_path = team2, public as $$
  select location_id from team2.profiles where id = auth.uid()
$$;

-- The access level this user's role has on a menu; NULL when they have no role
-- assigned or the matrix has no row for that menu.
create or replace function team2.matrix_access(p_menu text) returns text
language sql stable security definer set search_path = team2, public as $$
  select rp.access
    from team2.profiles p
    join team2.role_permissions rp
      on rp.role_id = p.role_id and rp.menu_id = p_menu
   where p.id = auth.uid()
$$;

-- Everyone below the signed-in user in the reporting tree (any depth).
create or replace function team2.in_my_team(p_user uuid) returns boolean
language sql stable security definer set search_path = team2, public as $$
  with recursive tree as (
    select id from team2.profiles where reporting_to = auth.uid()
    union
    select p.id from team2.profiles p join tree t on p.reporting_to = t.id
  )
  select coalesce(p_user = auth.uid(), false) or exists (select 1 from tree where id = p_user)
$$;

-- Who may approve / act on a record that belongs to p_user.
create or replace function team2.can_approve_for(p_user uuid) returns boolean
language sql stable security definer set search_path = team2, public as $$
  select team2.is_admin()
      or (p_user <> auth.uid() and team2.in_my_team(p_user))
$$;

-- ---------------------------------------------------------------------------
-- Masters: "own" = this user created the row, or the row is at their location.
-- ---------------------------------------------------------------------------
create or replace function team2.is_own(p_created_by uuid, p_location uuid) returns boolean
language sql stable security definer set search_path = team2, public as $$
  select coalesce(p_created_by = auth.uid(), false)
      or (p_location is not null and p_location = team2.my_location_id())
$$;

create or replace function team2.can_view(p_menu text, p_created_by uuid, p_location uuid)
returns boolean language sql stable security definer set search_path = team2, public as $$
  select case
    when team2.is_admin() then true
    -- No role assigned, or the matrix says nothing: stay readable so a half-configured
    -- matrix cannot lock the app out.
    when team2.matrix_access(p_menu) is null then true
    when team2.matrix_access(p_menu) in ('view_all','edit_all') then true
    when team2.matrix_access(p_menu) in ('view_own','edit_own') then team2.is_own(p_created_by, p_location)
    else false
  end
$$;

create or replace function team2.can_edit(p_menu text, p_created_by uuid, p_location uuid)
returns boolean language sql stable security definer set search_path = team2, public as $$
  select case
    when team2.is_admin() then true
    when team2.matrix_access(p_menu) is null then team2.is_manager()
    when team2.matrix_access(p_menu) = 'edit_all' then true
    when team2.matrix_access(p_menu) = 'edit_own' then team2.is_own(p_created_by, p_location)
    else false
  end
$$;

-- ---------------------------------------------------------------------------
-- Transactional records belong to an employee, so "own" means the employee —
-- and, for a manager, anyone reporting to them.
-- ---------------------------------------------------------------------------
create or replace function team2.can_view_record(p_menu text, p_user uuid)
returns boolean language sql stable security definer set search_path = team2, public as $$
  select case
    when team2.is_admin() then true
    when p_user = auth.uid() then true                      -- your own record, always
    when team2.matrix_access(p_menu) is null then team2.in_my_team(p_user)
    when team2.matrix_access(p_menu) in ('view_all','edit_all') then true
    when team2.matrix_access(p_menu) in ('view_own','edit_own') then team2.in_my_team(p_user)
    else false
  end
$$;

create or replace function team2.can_edit_record(p_menu text, p_user uuid)
returns boolean language sql stable security definer set search_path = team2, public as $$
  select case
    when team2.is_admin() then true
    when team2.matrix_access(p_menu) is null then team2.in_my_team(p_user)
    when team2.matrix_access(p_menu) = 'edit_all' then true
    when team2.matrix_access(p_menu) = 'edit_own' then team2.in_my_team(p_user)
    else false
  end
$$;

grant execute on all functions in schema team2 to authenticated;

-- ---------------------------------------------------------------------------
-- Master policies. Delete is deliberately NOT matrix-driven — manager and above,
-- and they still need edit rights.
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['locations','departments','designations','roles','shifts','holidays'] loop
    execute format('create index if not exists idx_team2_%s_active on team2.%I(active)', t, t);

    execute format('drop trigger if exists %s_touch_updated_at on team2.%I', t, t);
    execute format('create trigger %s_touch_updated_at before update on team2.%I
                    for each row execute function team2.touch_updated_at()', t, t);

    execute format('alter table team2.%I enable row level security', t);

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

-- A location IS its own location, so `id` is the location for "own" checks.
drop policy if exists locations_select on team2.locations;
create policy locations_select on team2.locations for select to authenticated
  using (team2.can_view('locations', created_by, id));

drop policy if exists locations_update on team2.locations;
create policy locations_update on team2.locations for update to authenticated
  using (team2.can_edit('locations', created_by, id))
  with check (team2.can_edit('locations', created_by, id));
