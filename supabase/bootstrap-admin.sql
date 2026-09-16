-- Run manually in Supabase SQL Editor after creating the first Auth user.
-- Replace both placeholders. This is an operator step, never an app endpoint.
insert into public.profiles(id,full_name,role,active)
values ('REPLACE_WITH_AUTH_USER_UUID'::uuid,'REPLACE_WITH_ADMIN_NAME','super_admin',true);
