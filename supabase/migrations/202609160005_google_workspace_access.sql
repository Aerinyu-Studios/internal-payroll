-- Configure the Google provider and the company's first administrator before enabling.
begin;
create function private.google_workspace_member() returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from auth.users u join auth.identities i on i.user_id=u.id
  where u.id=auth.uid() and u.email_confirmed_at is not null
   and lower(u.email) ~ '^[^@]+@aerinyustudios[.]com$'
   and i.provider='google'
   and i.identity_data->'custom_claims'->>'hd'='aerinyustudios.com'
   and lower(i.identity_data->>'email')=lower(u.email)
   and i.identity_data->>'email_verified'='true'
 ) and coalesce(auth.jwt()->'amr','[]'::jsonb) @> '[{"method":"oauth"}]'::jsonb
$$;
revoke all on function private.google_workspace_member() from public,anon;
grant execute on function private.google_workspace_member() to authenticated;
create or replace function private.role() returns text language sql stable security definer set search_path='' as $$select role::text from public.profiles where id=auth.uid() and active and private.google_workspace_member()$$;
drop policy profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using(private.google_workspace_member() and (id=auth.uid() or private.role()='super_admin'));
commit;
