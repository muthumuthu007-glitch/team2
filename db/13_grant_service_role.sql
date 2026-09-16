-- Team2 — let the edge functions (service_role) use the team2 tables.
-- Applied as migration `team2_grant_service_role` (2026-09-16).
--
-- The first migration granted table rights only to `authenticated`. service_role
-- bypasses RLS but still needs ordinary table privileges, so every edge function
-- (team2-admin, team2-whatsapp, team2-sms) failed to read team2.profiles and
-- answered "Admins only". Mono hit the same gap.

grant usage on schema team2 to service_role;
grant select, insert, update, delete on all tables    in schema team2 to service_role;
grant usage, select                  on all sequences in schema team2 to service_role;
grant execute                        on all functions in schema team2 to service_role;

alter default privileges in schema team2 grant select, insert, update, delete on tables    to service_role;
alter default privileges in schema team2 grant usage, select                  on sequences to service_role;
alter default privileges in schema team2 grant execute                        on functions to service_role;

notify pgrst, 'reload schema';
