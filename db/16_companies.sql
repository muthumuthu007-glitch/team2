-- Team2 — Company master. Applied as migration `team2_companies`.
--
-- ⚠ This table alone does NOT separate company data. Until every data table carries
-- company_id and its RLS policy filters on it, any admin still sees all data.
-- Create real customer companies only after that work is done.

create sequence if not exists team2.company_code_seq start 1;

create table if not exists team2.companies (
  id           uuid primary key default gen_random_uuid(),
  company_code text unique not null
               default 'CMP-' || lpad(nextval('team2.company_code_seq')::text, 3, '0'),
  name         text not null,
  address      text,
  gstin        text,
  email        text,
  phone        text,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  created_by   uuid references team2.profiles(id) on delete set null,
  updated_at   timestamptz not null default now()
);

create unique index if not exists uq_team2_companies_name on team2.companies (lower(name));

do $$
begin
  -- Indian GSTIN: 2-digit state, 5 letters, 4 digits, letter, entity digit/letter, Z, checksum.
  if not exists (select 1 from pg_constraint where conname = 'companies_gstin_chk') then
    alter table team2.companies add constraint companies_gstin_chk
      check (gstin is null or gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'companies_email_chk') then
    alter table team2.companies add constraint companies_email_chk
      check (email is null or email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$');
  end if;
end $$;

drop trigger if exists companies_touch_updated_at on team2.companies;
create trigger companies_touch_updated_at before update on team2.companies
  for each row execute function team2.touch_updated_at();

-- Which company a person belongs to. Nullable while the app is still single-company.
alter table team2.profiles
  add column if not exists company_id uuid references team2.companies(id) on delete set null;

create index if not exists idx_team2_profiles_company on team2.profiles(company_id);

alter table team2.companies enable row level security;

-- Only the product owner (superadmin) manages companies; admins may read.
drop policy if exists companies_select on team2.companies;
create policy companies_select on team2.companies for select to authenticated
  using (team2.is_admin());

drop policy if exists companies_write on team2.companies;
create policy companies_write on team2.companies for all to authenticated
  using (team2.my_role() = 'superadmin') with check (team2.my_role() = 'superadmin');

grant select, insert, update, delete on team2.companies to authenticated;
grant usage, select on sequence team2.company_code_seq to authenticated;

notify pgrst, 'reload schema';
