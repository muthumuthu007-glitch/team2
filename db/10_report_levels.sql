-- Team2 — second and third reporting levels on the staff record.
-- Applied as migration `team2_profiles_report_levels`.
--
-- `reporting_to` stays level 1 and is the ONLY one team2.in_my_team() walks, so it is
-- what decides who a manager can see. Levels 2 and 3 are escalation contacts for
-- approvals and reports; they grant no visibility on their own.

alter table team2.profiles
  add column if not exists reporting_to_2 uuid references team2.profiles(id) on delete set null,
  add column if not exists reporting_to_3 uuid references team2.profiles(id) on delete set null;

notify pgrst, 'reload schema';
