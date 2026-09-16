-- Team2 — Unit geofences. Applied as migration `team2_unit_geofence_polygon`.
-- The table keeps the name `locations`: profiles.location_id, the RLS helpers and
-- role_permissions.menu_id = 'locations' all key on it. Only the app label says "Unit".

alter table team2.locations
  add column if not exists geofence_type     text not null default 'circle',
  add column if not exists geofence_polygon  jsonb,
  add column if not exists geofence_buffer_m integer not null default 100;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'locations_geofence_type_chk') then
    alter table team2.locations add constraint locations_geofence_type_chk
      check (geofence_type in ('circle', 'polygon'));
  end if;
  -- A polygon needs at least 3 vertices; a circle needs none.
  if not exists (select 1 from pg_constraint where conname = 'locations_geofence_polygon_chk') then
    alter table team2.locations add constraint locations_geofence_polygon_chk
      check (
        geofence_type <> 'polygon'
        or (jsonb_typeof(geofence_polygon) = 'array' and jsonb_array_length(geofence_polygon) >= 3)
      );
  end if;
  if not exists (select 1 from pg_constraint where conname = 'locations_geofence_buffer_chk') then
    alter table team2.locations add constraint locations_geofence_buffer_chk
      check (geofence_buffer_m >= 0 and geofence_buffer_m <= 5000);
  end if;
end $$;

notify pgrst, 'reload schema';
