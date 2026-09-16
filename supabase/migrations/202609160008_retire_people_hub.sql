-- Retire the People hub without deleting personnel, finance or onboarding data.
-- Safe after migrations 001-005, or after 006/007. Re-running is safe.
begin;
do $$declare fn record;begin
 for fn in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=any(array['people_directory','employee_detail','onboard_employee','update_employee','set_department_head','set_employee_checklist','request_employee_change','review_employee_change','claim_workspace_account','find_employee_auth_user','finish_workspace_account','fail_workspace_account','existing_employee_account','link_employee_signin']) loop
  execute format('revoke all on function %s from public, anon, authenticated',fn.signature);
 end loop;
end$$;
-- Keep all saved data and existing IDs; restore manual employee-ID entry.
drop trigger if exists employee_id_auto on public.personnel;
drop trigger if exists employee_id_auto_update on public.personnel;
drop trigger if exists protect_company_identity on public.personnel;
drop trigger if exists employee_status_access on public.personnel;
-- Only portal-only accounts lose access. Existing finance roles remain unchanged.
with retired as (
 update public.profiles set active=false where role::text='employee' and active returning id
)
insert into public.audit_logs(actor_id,actor_name,action,object_id,record_id,before_state,after_state)
select null,'System','Employee portal access disabled',id,null,null,'{"active":false}'::jsonb from retired;
create or replace function public.save_profile(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare obj uuid;old_value jsonb;begin
 perform private.require_roles(array['super_admin']);
 if coalesce(input->>'role','') not in ('super_admin','finance','manager','viewer') then raise exception 'Choose a finance workspace role.' using errcode='42501';end if;perform pg_advisory_xact_lock(20260916);
 obj=(input->>'id')::uuid;select to_jsonb(p) into old_value from public.profiles p where id=obj for update;
 if obj=auth.uid() and (input->>'role'<>'super_admin' or not (input->>'active')::boolean) then raise exception 'You cannot remove your own administrative access.';end if;
 insert into public.profiles(id,full_name,role,active) values(obj,input->>'full_name',(input->>'role')::public.app_role,(input->>'active')::boolean) on conflict(id) do update set full_name=excluded.full_name,role=excluded.role,active=excluded.active;
 perform private.audit('User access changed',obj,null,old_value,input);return jsonb_build_object('id',obj);
end$$;
revoke all on function public.save_profile(jsonb) from public,anon;
grant execute on function public.save_profile(jsonb) to authenticated;
commit;
