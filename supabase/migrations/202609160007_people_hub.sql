begin;
alter table public.personnel add column manager_id uuid references public.personnel;
alter table public.personnel add column team text not null default '';
alter table public.personnel add column end_date date;
alter table public.personnel add column auth_user_id uuid unique references auth.users;
alter table public.personnel add column onboarding_request_id uuid unique;
alter table public.personnel add constraint personnel_not_own_manager check(manager_id is distinct from id);
alter table public.personnel add constraint employment_dates check(end_date is null or end_date >= start_date);
create unique index personnel_company_email_unique on public.personnel(lower(email)) where lower(email) ~ '^[^@]+@aerinyustudios[.]com$';
alter table public.departments add column head_id uuid references public.personnel;

-- A single studio-wide sequence, continuing after 010. It does not reset yearly.
create table private.employee_counter(singleton boolean primary key default true check(singleton),last_number integer not null check(last_number between 0 and 999));
insert into private.employee_counter values(true,greatest(10,coalesce((select max(right(personnel_code,3)::integer) from public.personnel where personnel_code ~ '^[0-9]{7}$'),0)));
revoke all on private.employee_counter from public,anon,authenticated;
create function private.allocate_employee_id(hired date) returns text language plpgsql security definer set search_path='' as $$
declare n integer;begin
 update private.employee_counter set last_number=last_number+1 where singleton and last_number<999 returning last_number into n;
 if n is null then raise exception 'Employee sequence has reached 999. Contact your administrator before adding another employee.';end if;
 return to_char(hired,'YY')||lpad(floor(random()*100)::integer::text,2,'0')||lpad(n::text,3,'0');
end$$;
create function private.prepare_employee_id() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.personnel_code is null or trim(new.personnel_code)='' then new.personnel_code=private.allocate_employee_id(new.start_date);
 elsif new.personnel_code ~ '^[0-9]{7}$' then update private.employee_counter set last_number=greatest(last_number,right(new.personnel_code,3)::integer) where singleton;end if;
 return new;end$$;
create trigger employee_id_auto before insert on public.personnel for each row execute function private.prepare_employee_id();
-- Keep allocation ahead of validation; existing manual edits also advance the floor.
create trigger employee_id_auto_update before update of personnel_code on public.personnel for each row execute function private.prepare_employee_id();

create table public.employee_private(personnel_id uuid primary key references public.personnel,personal_email text not null default '',phone text not null default '',date_of_birth date,residential_address text not null default '',country_of_residence text not null default '',version integer not null default 1);
create table public.employee_payment_profiles(personnel_id uuid primary key references public.personnel,payment_method text not null default 'bank_transfer',currency text not null default 'MYR',bank_name text not null default '',account_holder text not null default '',account_number text not null default '',version integer not null default 1);
create table public.employee_change_requests(id uuid primary key default gen_random_uuid(),personnel_id uuid not null references public.personnel,kind text not null check(kind in ('personal','payment')),payload jsonb not null,base_version integer not null,status text not null default 'pending' check(status in ('pending','approved','rejected')),created_by uuid not null references public.profiles,created_at timestamptz not null default now(),reviewed_by uuid references public.profiles,reviewed_at timestamptz);
create unique index one_pending_employee_change on public.employee_change_requests(personnel_id,kind) where status='pending';
create table public.employee_checklist(id uuid primary key default gen_random_uuid(),personnel_id uuid not null references public.personnel,title text not null,done boolean not null default false,unique(personnel_id,title));
create table public.workspace_provisioning(personnel_id uuid primary key references public.personnel,desired_email text not null unique,given_name text not null,family_name text not null,state text not null default 'pending' check(state in ('pending','processing','failed','complete')),google_user_id text unique,claim_token uuid,lease_until timestamptz,last_error text,updated_at timestamptz not null default now());
insert into public.employee_private(personnel_id,phone) select id,phone from public.personnel;
alter table public.employee_change_requests add constraint employee_change_size check(length(payload::text)<=8000);
alter table public.employee_payment_profiles add constraint employee_payment_method check(payment_method in ('bank_transfer','cash','wallet','other'));
alter table public.employee_payment_profiles add constraint employee_payment_currency check(currency in ('MYR','USD','AUD','SGD','EUR','GBP','JPY','KRW','IDR','THB','PHP','INR','CAD','NZD','CNY','HKD'));
do $$declare t text;begin foreach t in array array['employee_private','employee_payment_profiles','employee_change_requests','employee_checklist','workspace_provisioning'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);end loop;end$$;

-- Employees receive the deliberately limited directory RPC, never raw finance tables.
do $$declare t text;begin foreach t in array array['departments','projects','personnel','monthly_records','work_items','adjustments'] loop execute format('drop policy member_read on public.%I',t);execute format('create policy member_read on public.%I for select to authenticated using(private.role() in (''super_admin'',''finance'',''manager'',''viewer''))',t);end loop;end$$;
create function private.own_person(person_id uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.personnel where id=person_id and auth_user_id=auth.uid())$$;
create function public.people_directory() returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform private.require_roles(array['super_admin','finance','manager','viewer','employee']);
 return jsonb_build_object('profile',(select to_jsonb(p) from public.profiles p where id=auth.uid()),'own_person_id',(select id from public.personnel where auth_user_id=auth.uid()),
 'people',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'personnel_code',p.personnel_code,'name',coalesce(nullif(p.display_name,''),p.legal_name),'email',p.email,'department_id',p.department_id,'department',d.name,'position',p.position,'team',p.team,'manager_id',p.manager_id,'status',p.status,'engagement',p.engagement,'start_date',p.start_date) order by p.legal_name),'[]') from public.personnel p join public.departments d on d.id=p.department_id),
 'departments',(select coalesce(jsonb_agg(to_jsonb(d) order by name),'[]') from public.departments d),
 'next_sequence',case when private.role()='super_admin' then (select last_number+1 from private.employee_counter) else null end,
 'onboarding',case when private.role()='super_admin' then (select coalesce(jsonb_agg(jsonb_build_object('personnel_id',personnel_id,'desired_email',desired_email,'state',state,'last_error',last_error,'updated_at',updated_at)),'[]') from public.workspace_provisioning) else '[]'::jsonb end);
end$$;
create function public.employee_detail(person_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare own boolean;admin boolean;fin boolean;begin
 perform private.require_roles(array['super_admin','finance','manager','viewer','employee']);
 if not exists(select 1 from public.personnel where id=person_id) then raise exception 'Employee not found.';end if;
 own=private.own_person(person_id);admin=private.role()='super_admin';fin=private.role() in ('super_admin','finance');
 if own or admin or fin then perform private.audit('Employee restricted profile viewed',person_id,null,null,jsonb_build_object('personal',own or admin,'payment',own or fin));end if;
 return jsonb_build_object('employment',case when own or admin then (select jsonb_build_object('legal_name',legal_name,'display_name',display_name,'engagement',engagement,'department_id',department_id,'manager_id',manager_id,'team',team,'position',position,'status',status,'start_date',start_date,'end_date',end_date,'version',version) from public.personnel where id=person_id) else null end,
 'personal',case when own or admin then (select to_jsonb(x)-'personnel_id' from public.employee_private x where personnel_id=person_id) else null end,
 'payment',case when own or fin then (select to_jsonb(x)-'personnel_id' from public.employee_payment_profiles x where personnel_id=person_id) else null end,
 'checklist',case when own or admin then (select coalesce(jsonb_agg(to_jsonb(x) order by title),'[]') from public.employee_checklist x where personnel_id=person_id) else '[]'::jsonb end,
 'requests',(select coalesce(jsonb_agg(to_jsonb(x) order by created_at desc),'[]') from public.employee_change_requests x where personnel_id=person_id and (own or (kind='personal' and admin) or (kind='payment' and fin))));
end$$;

create function private.check_reporting_line(person_id uuid,manager uuid) returns void language plpgsql security definer set search_path='' as $$begin
 if manager is not null and not exists(select 1 from public.personnel where id=manager and status='active') then raise exception 'Select an active manager.';end if;
 if manager=person_id or exists(with recursive chain as (select id,manager_id from public.personnel where id=manager union select p.id,p.manager_id from public.personnel p join chain c on p.id=c.manager_id) select 1 from chain where id=person_id) then raise exception 'This reporting relationship would create a cycle.';end if;
end$$;
create function public.onboard_employee(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare person_id uuid;mail text;begin
 perform private.require_roles(array['super_admin']);
 perform pg_advisory_xact_lock(160007);
 select id into person_id from public.personnel where onboarding_request_id=(input->>'request_id')::uuid;
 if found then return jsonb_build_object('id',person_id);end if;
 mail=lower(trim(input->>'email'));
 if mail !~ '^[a-z0-9]+([._-][a-z0-9]+)*@aerinyustudios[.]com$' then raise exception 'Enter a valid aerinyustudios.com work email.';end if;
 if exists(select 1 from public.personnel where lower(email)=mail) then raise exception 'This work email is already assigned.' using errcode='23505';end if;
 if length(trim(input->>'given_name'))<1 or length(trim(input->>'family_name'))<1 then raise exception 'First and last names are required.';end if;
 perform private.check_reporting_line(null,(input->>'manager_id')::uuid);
 insert into public.personnel(personnel_code,legal_name,display_name,engagement,department_id,position,email,phone,start_date,status,currency,payment_structure,notes,manager_id,team,onboarding_request_id)
 values(null,trim(input->>'legal_name'),coalesce(input->>'display_name',''),input->>'engagement',(input->>'department_id')::uuid,trim(input->>'position'),mail,'',(input->>'start_date')::date,'active',input->>'currency','fixed','',(input->>'manager_id')::uuid,coalesce(input->>'team',''),(input->>'request_id')::uuid) returning id into person_id;
 insert into public.employee_private(personnel_id,personal_email,phone,date_of_birth,residential_address,country_of_residence) values(person_id,coalesce(input->>'personal_email',''),coalesce(input->>'phone',''),nullif(input->>'date_of_birth','')::date,coalesce(input->>'residential_address',''),coalesce(input->>'country_of_residence',''));
 insert into public.employee_payment_profiles(personnel_id,currency) values(person_id,input->>'currency');
 insert into public.workspace_provisioning(personnel_id,desired_email,given_name,family_name) values(person_id,mail,trim(input->>'given_name'),trim(input->>'family_name'));
 insert into public.employee_checklist(personnel_id,title) select person_id,unnest(array['Employment documents completed','Company account handed over','Payment details verified','Project access assigned','Orientation completed']);
 perform private.audit('Employee onboarded',person_id,null,null,jsonb_build_object('employee_id',(select personnel_code from public.personnel where id=person_id),'email',mail));
 return jsonb_build_object('id',person_id);
end$$;
create function public.update_employee(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare p public.personnel;begin
 perform private.require_roles(array['super_admin']);perform pg_advisory_xact_lock(160007);
 select * into strict p from public.personnel where id=(input->>'id')::uuid for update;
 if p.version<>(input->>'expected_version')::integer then raise exception 'This employee changed. Reload before saving.' using errcode='40001';end if;
 if p.auth_user_id=auth.uid() and input->>'status'<>'active' then raise exception 'Another administrator must change your employment status.';end if;
 perform private.check_reporting_line(p.id,(input->>'manager_id')::uuid);
 update public.personnel set legal_name=trim(input->>'legal_name'),display_name=input->>'display_name',department_id=(input->>'department_id')::uuid,position=input->>'position',team=input->>'team',manager_id=(input->>'manager_id')::uuid,engagement=input->>'engagement',status=input->>'status',end_date=nullif(input->>'end_date','')::date,version=version+1 where id=p.id;
 if input->>'status'<>'active' and p.auth_user_id is not null then update public.profiles set active=false where id=p.auth_user_id;end if;
 update public.departments set head_id=null where head_id=p.id and (id<>(input->>'department_id')::uuid or input->>'status'<>'active');
 perform private.audit('Employee organisation updated',p.id,null,null,jsonb_build_object('department_id',input->>'department_id','manager_id',input->>'manager_id','status',input->>'status'));
 return jsonb_build_object('id',p.id);
end$$;
create function public.set_department_head(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform private.require_roles(array['super_admin']);
 if input->>'head_id' is not null and not exists(select 1 from public.personnel where id=(input->>'head_id')::uuid and department_id=(input->>'id')::uuid and status='active') then raise exception 'Choose an active employee in this department.';end if;
 update public.departments set head_id=(input->>'head_id')::uuid where id=(input->>'id')::uuid;
 perform private.audit('Department head updated',(input->>'id')::uuid,null,null,jsonb_build_object('head_id',input->>'head_id'));return '{}'::jsonb;
end$$;
create function public.set_employee_checklist(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare person_id uuid;begin
 perform private.require_roles(array['super_admin']);update public.employee_checklist set done=(input->>'done')::boolean where id=(input->>'id')::uuid returning personnel_id into person_id;
 if person_id is null then raise exception 'Checklist item not found.';end if;
 perform private.audit('Onboarding checklist updated',person_id,null,null,jsonb_build_object('item_id',input->>'id','done',input->'done'));return '{}'::jsonb;
end$$;

create function public.request_employee_change(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare person_id uuid:=(input->>'personnel_id')::uuid;k text:=input->>'kind';v integer;obj uuid;begin
 perform private.require_roles(array['super_admin','finance','manager','viewer','employee']);
 if not private.own_person(person_id) and not (private.role()='super_admin' or (private.role()='finance' and k='payment')) then raise exception 'Permission denied.' using errcode='42501';end if;
 if k='personal' then
  if exists(select 1 from jsonb_object_keys(input->'payload') x where x not in ('personal_email','phone','date_of_birth','residential_address','country_of_residence')) then raise exception 'Unsupported personal field.';end if;
  insert into public.employee_private(personnel_id) values(person_id) on conflict do nothing;select version into v from public.employee_private where personnel_id=person_id;
 elsif k='payment' then
  if exists(select 1 from jsonb_object_keys(input->'payload') x where x not in ('payment_method','currency','bank_name','account_holder','account_number')) then raise exception 'Unsupported payment field.';end if;
  insert into public.employee_payment_profiles(personnel_id) values(person_id) on conflict do nothing;select version into v from public.employee_payment_profiles where personnel_id=person_id;
 else raise exception 'Unknown change type.';end if;
 insert into public.employee_change_requests(personnel_id,kind,payload,base_version,created_by) values(person_id,k,input->'payload',v,auth.uid()) returning id into obj;
 perform private.audit('Employee change requested',person_id,null,null,jsonb_build_object('request_id',obj,'kind',k));return jsonb_build_object('id',obj);
end$$;
create function public.review_employee_change(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare r public.employee_change_requests;v integer;begin
 select * into strict r from public.employee_change_requests where id=(input->>'id')::uuid for update;
 perform private.require_roles(case when r.kind='payment' then array['super_admin','finance'] else array['super_admin'] end);
 if r.status<>'pending' then raise exception 'This request has already been reviewed.';end if;
 if input->>'decision' not in ('approved','rejected') then raise exception 'Choose approve or reject.';end if;
 if input->>'decision'='approved' then
  if r.kind='personal' then
   select version into v from public.employee_private where personnel_id=r.personnel_id for update;
   if v<>r.base_version then raise exception 'These details changed. Reject this request and submit a fresh one.';end if;
   update public.employee_private set personal_email=coalesce(r.payload->>'personal_email',''),phone=coalesce(r.payload->>'phone',''),date_of_birth=nullif(r.payload->>'date_of_birth','')::date,residential_address=coalesce(r.payload->>'residential_address',''),country_of_residence=coalesce(r.payload->>'country_of_residence',''),version=version+1 where personnel_id=r.personnel_id;
  else
   select version into v from public.employee_payment_profiles where personnel_id=r.personnel_id for update;
   if v<>r.base_version then raise exception 'These details changed. Reject this request and submit a fresh one.';end if;
   update public.employee_payment_profiles set payment_method=coalesce(r.payload->>'payment_method','bank_transfer'),currency=coalesce(r.payload->>'currency','MYR'),bank_name=coalesce(r.payload->>'bank_name',''),account_holder=coalesce(r.payload->>'account_holder',''),account_number=coalesce(r.payload->>'account_number',''),version=version+1 where personnel_id=r.personnel_id;
   -- Keep the existing finance payment-information panel consistent.
   insert into public.personnel_payment_details(personnel_id,payment_info) values(r.personnel_id,concat_ws(E'\n',r.payload->>'bank_name',r.payload->>'account_holder',r.payload->>'account_number',r.payload->>'currency',replace(r.payload->>'payment_method','_',' '))) on conflict(personnel_id) do update set payment_info=excluded.payment_info;
  end if;
 end if;
 update public.employee_change_requests set status=input->>'decision',reviewed_by=auth.uid(),reviewed_at=now() where id=r.id;
 perform private.audit('Employee change reviewed',r.personnel_id,null,null,jsonb_build_object('request_id',r.id,'kind',r.kind,'decision',input->>'decision'));return '{}'::jsonb;
end$$;

create function public.claim_workspace_account(person_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare j public.workspace_provisioning;p public.personnel;token uuid:=gen_random_uuid();begin
 perform private.require_roles(array['super_admin']);
 select * into strict p from public.personnel where id=person_id for update;
 select * into strict j from public.workspace_provisioning where personnel_id=person_id for update;
 if p.status<>'active' then raise exception 'Only active employees can receive company accounts.';end if;
 if j.state='complete' then return jsonb_build_object('complete',true,'email',j.desired_email);end if;
 if j.state='processing' and j.lease_until>now() then raise exception 'Account creation is already in progress. Wait a moment before retrying.' using errcode='40001';end if;
 update public.workspace_provisioning set state='processing',claim_token=token,lease_until=now()+interval '3 minutes',last_error=null,updated_at=now() where personnel_id=person_id;
 return jsonb_build_object('id',p.id,'employee_id',p.personnel_code,'email',j.desired_email,'given_name',j.given_name,'family_name',j.family_name,'department',(select name from public.departments where id=p.department_id),'position',p.position,'manager_email',(select email from public.personnel where id=p.manager_id),'claim_token',token);
end$$;
create function public.find_employee_auth_user(person_id uuid) returns uuid language plpgsql security definer set search_path='' as $$declare result uuid;begin
 perform private.require_roles(array['super_admin']);select u.id into result from auth.users u join public.workspace_provisioning j on lower(u.email)=j.desired_email where j.personnel_id=person_id;return result;
end$$;
create function public.finish_workspace_account(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare j public.workspace_provisioning;p public.personnel;uid uuid:=(input->>'auth_user_id')::uuid;begin
 perform private.require_roles(array['super_admin']);
 select * into strict p from public.personnel where id=(input->>'personnel_id')::uuid for update;
 select * into strict j from public.workspace_provisioning where personnel_id=p.id for update;
 if j.claim_token is distinct from (input->>'claim_token')::uuid or j.state<>'processing' then raise exception 'This onboarding attempt expired. Retry from the employee profile.';end if;
 if not exists(select 1 from auth.users where id=uid and lower(email)=j.desired_email) then raise exception 'Company sign-in account does not match this employee.';end if;
 if p.status<>'active' then raise exception 'Employee is no longer active. Review the company account in Google Admin.';end if;
 insert into public.profiles(id,full_name,role,active) values(uid,p.legal_name,'employee',true) on conflict(id) do nothing;
 update public.personnel set auth_user_id=uid,version=version+1 where id=p.id;
 update public.workspace_provisioning set state='complete',google_user_id=input->>'google_user_id',claim_token=null,lease_until=null,last_error=null,updated_at=now() where personnel_id=p.id;
 perform private.audit('Company account provisioned',p.id,null,null,jsonb_build_object('email',j.desired_email));return jsonb_build_object('email',j.desired_email);
end$$;
create function public.fail_workspace_account(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform private.require_roles(array['super_admin']);update public.workspace_provisioning set state='failed',last_error=left(input->>'message',500),claim_token=null,lease_until=null,updated_at=now() where personnel_id=(input->>'personnel_id')::uuid and claim_token=(input->>'claim_token')::uuid;return '{}'::jsonb;
end$$;
create function public.existing_employee_account(person_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare p public.personnel;begin
 perform private.require_roles(array['super_admin']);select * into strict p from public.personnel where id=person_id;
 if p.status<>'active' then raise exception 'Only active employees can receive portal access.';end if;
 if exists(select 1 from public.workspace_provisioning where personnel_id=p.id) then raise exception 'Use this employee''s onboarding account setup.';end if;
 return jsonb_build_object('id',p.id,'employee_id',p.personnel_code,'email',lower(p.email),'name',p.legal_name,'auth_user_id',(select id from auth.users where lower(email)=lower(p.email)));
end$$;
create function public.link_employee_signin(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare p public.personnel;uid uuid:=(input->>'auth_user_id')::uuid;begin
 perform private.require_roles(array['super_admin']);select * into strict p from public.personnel where id=(input->>'personnel_id')::uuid for update;
 if p.status<>'active' or lower(p.email) !~ '^[^@]+@aerinyustudios[.]com$' then raise exception 'An active employee with a company email is required.';end if;
 if not exists(select 1 from auth.users where id=uid and lower(email)=lower(p.email)) then raise exception 'Sign-in email does not match this employee.';end if;
 insert into public.profiles(id,full_name,role,active) values(uid,p.legal_name,'employee',true) on conflict(id) do nothing;
 update public.personnel set auth_user_id=uid,version=version+1 where id=p.id;
 perform private.audit('Existing employee portal linked',p.id,null,null,jsonb_build_object('email',p.email));return '{}'::jsonb;
end$$;
-- Existing finance edit forms may update details, but not silently rename provisioned identities.
create function private.protect_company_identity() returns trigger language plpgsql set search_path='' as $$begin
 if (new.email is distinct from old.email or new.personnel_code is distinct from old.personnel_code) and (old.auth_user_id is not null or exists(select 1 from public.workspace_provisioning where personnel_id=old.id)) then raise exception 'Company email and employee ID are fixed after onboarding.';end if;return new;
end$$;
create trigger protect_company_identity before update on public.personnel for each row execute function private.protect_company_identity();
-- Applies equally to status edits from the existing finance personnel form.
create function private.employee_status_access() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.status<>'active' and new.auth_user_id is not null then
  if auth.uid() is not null and coalesce(private.role(),'')<>'super_admin' then raise exception 'An administrator must change the status of an employee with portal access.' using errcode='42501';end if;
  if new.auth_user_id=auth.uid() then raise exception 'Another administrator must change your employment status.';end if;
  update public.profiles set active=false where id=new.auth_user_id;
 end if;return new;end$$;
create trigger employee_status_access after update of status on public.personnel for each row execute function private.employee_status_access();

do $$declare f text;begin foreach f in array array['people_directory()','employee_detail(uuid)','onboard_employee(jsonb)','update_employee(jsonb)','set_department_head(jsonb)','set_employee_checklist(jsonb)','request_employee_change(jsonb)','review_employee_change(jsonb)','claim_workspace_account(uuid)','find_employee_auth_user(uuid)','finish_workspace_account(jsonb)','fail_workspace_account(jsonb)','existing_employee_account(uuid)','link_employee_signin(jsonb)'] loop execute 'revoke all on function public.'||f||' from public, anon';execute 'grant execute on function public.'||f||' to authenticated';end loop;end$$;
revoke all on function private.allocate_employee_id(date),private.prepare_employee_id(),private.own_person(uuid),private.check_reporting_line(uuid,uuid),private.protect_company_identity(),private.employee_status_access() from public,anon,authenticated;
commit;
