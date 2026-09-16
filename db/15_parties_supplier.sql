-- Team2 — "Customer / Site" becomes "Supplier". Applied as migration `team2_parties_supplier`.
-- The table keeps the name `parties` (menu id and permission matrix key 'parties').
alter table team2.parties drop constraint if exists parties_party_type_check;
alter table team2.parties add constraint parties_party_type_check
  check (party_type in ('supplier', 'customer', 'prospect', 'dealer', 'vendor', 'site', 'other'));
alter table team2.parties alter column party_type set default 'supplier';

create index if not exists idx_team2_parties_name_lower on team2.parties (lower(name));

notify pgrst, 'reload schema';
