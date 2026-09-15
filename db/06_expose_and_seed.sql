-- Team2 — expose the schema to PostgREST and seed the standard masters.
-- Applied as migration `team2_expose_to_postgrest_and_seed_masters`.
--
-- ⚠ `mono`, `muthus` and `asset` MUST stay in this list or those apps break.
alter role authenticator set pgrst.db_schemas = 'public, graphql_public, mono, muthus, asset, team2';

-- Starter masters. All editable in the app; nothing here is business-specific.
insert into team2.shifts (name, start_time, end_time, week_offs)
select 'General', '09:30', '18:30', '{0}'
where not exists (select 1 from team2.shifts);

insert into team2.roles (name, description, is_admin)
select v.name, v.descr, v.adm
  from (values
    ('Admin',     'Full access to every menu',              true),
    ('Manager',   'Approves their team and sees its data',  false),
    ('Executive', 'Own attendance, leave and visits only',  false)
  ) as v(name, descr, adm)
where not exists (select 1 from team2.roles);

insert into team2.leave_types (name, short_name, is_paid, annual_quota)
select v.name, v.sn, v.paid, v.quota
  from (values
    ('Casual Leave',  'CL', true,  12),
    ('Sick Leave',    'SL', true,  12),
    ('Earned Leave',  'EL', true,  15),
    ('Loss of Pay',   'LOP', false, 0)
  ) as v(name, sn, paid, quota)
where not exists (select 1 from team2.leave_types);

insert into team2.visit_purposes (name)
select v.name
  from (values ('Sales Call'), ('Service Visit'), ('Collection'),
               ('Delivery'), ('Follow-up'), ('Other')) as v(name)
where not exists (select 1 from team2.visit_purposes);

notify pgrst, 'reload config';
notify pgrst, 'reload schema';


-- ---------------------------------------------------------------------------
-- Logins — run by hand, NOT part of the migration.
-- ---------------------------------------------------------------------------
-- Passwords are never written into this repo.
--
-- The superadmin 9894021299 (emp_code 01) was created on 2026-08-12 with the
-- block below. To add another login, change the mobile number, the password and
-- the profile fields. A GoTrue password login needs THREE things: the auth.users
-- row, a matching auth.identities row for the 'email' provider, and the profile.
--
--   do $$
--   declare uid uuid := gen_random_uuid();
--           mail text := '<mobile>@team2.app';
--   begin
--     insert into auth.users (
--       instance_id, id, aud, role, email, encrypted_password,
--       email_confirmed_at, created_at, updated_at,
--       raw_app_meta_data, raw_user_meta_data,
--       confirmation_token, recovery_token, email_change_token_new, email_change,
--       email_change_token_current, phone_change, phone_change_token,
--       reauthentication_token, is_super_admin, is_sso_user, is_anonymous
--     ) values (
--       '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
--       mail, extensions.crypt('<password>', extensions.gen_salt('bf')),
--       now(), now(), now(),
--       '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
--       '', '', '', '', '', '', '', '', false, false, false
--     );
--     insert into auth.identities (id, provider_id, user_id, identity_data, provider,
--                                  last_sign_in_at, created_at, updated_at)
--     values (gen_random_uuid(), uid, uid,
--             jsonb_build_object('sub', uid::text, 'email', mail,
--                                'email_verified', true, 'phone_verified', false),
--             'email', now(), now(), now());
--     insert into team2.profiles (id, username, name, role, emp_code, phone)
--     values (uid, '<mobile>', '<name>', 'staff', '<code>', '<mobile>');
--   end $$;
--
-- The empty strings matter: GoTrue errors on NULL token columns.
-- To reset a password:
--   update auth.users
--      set encrypted_password = extensions.crypt('<new>', extensions.gen_salt('bf'))
--    where email = '<mobile>@team2.app';
