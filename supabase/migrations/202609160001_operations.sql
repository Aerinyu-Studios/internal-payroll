-- Aerinyu Studios. Apply once to a dedicated Supabase project.
-- All financial writes are transactional RPCs. No application role receives direct write grants.
create schema if not exists private;
revoke all on schema private from public;
create type public.app_role as enum ('super_admin','finance','manager','viewer');
create type public.record_status as enum ('draft','submitted','approved','awaiting_payment','paid','archived');
create sequence private.personnel_number;
create sequence private.statement_number;
create sequence private.receipt_number;
create function private.next_number(sequence_name regclass,pad integer) returns text language plpgsql set search_path='' as $$declare n text;begin n=nextval(sequence_name)::text;return lpad(n,greatest(pad,length(n)),'0');end$$;
create table public.profiles(id uuid primary key references auth.users(id),full_name text not null,role public.app_role not null default 'viewer',active boolean not null default true,created_at timestamptz not null default now());
create table public.departments(id uuid primary key default gen_random_uuid(),name text not null unique check(length(name) between 1 and 150));
create table public.projects(id uuid primary key default gen_random_uuid(),name text not null unique check(length(name) between 1 and 150),status text not null default 'active' check(status in ('active','archived')));
create table public.personnel(
 id uuid primary key default gen_random_uuid(),personnel_code text not null unique default ('AE-'||private.next_number('private.personnel_number',4)),
 legal_name text not null check(length(legal_name) between 1 and 200),display_name text not null default '',engagement text not null check(engagement in ('employee','contractor','freelancer','other')),
 department_id uuid not null references public.departments,position text not null,email text not null,phone text not null default '',start_date date not null,status text not null check(status in ('active','inactive','suspended','departed')),
 currency text not null check(currency in ('MYR','USD','AUD','SGD','EUR','GBP','JPY','KRW','IDR','THB','PHP','INR','CAD','NZD','CNY','HKD')),default_rate numeric(16,4) not null default 0 check(default_rate>=0),payment_structure text not null check(payment_structure in ('fixed','hourly','per_task','project','custom')),notes text not null default '',version integer not null default 1,created_at timestamptz not null default now());
create table public.personnel_payment_details(personnel_id uuid primary key references public.personnel,payment_info text not null default '');
create table public.monthly_records(
 id uuid primary key default gen_random_uuid(),request_id uuid not null unique,statement_number text not null unique,personnel_id uuid not null references public.personnel,period date not null check(extract(day from period)=1),currency text not null,
 status public.record_status not null default 'draft',notes text not null default '',version integer not null default 1,snapshot jsonb,approved_by uuid references public.profiles,approved_by_name text,approved_at timestamptz,created_by uuid not null references public.profiles,created_at timestamptz not null default now(),unique(personnel_id,period));
create table public.work_items(id uuid primary key default gen_random_uuid(),record_id uuid not null references public.monthly_records on delete cascade,title text not null check(length(title) between 1 and 200),description text not null default '',project_id uuid references public.projects,completed_on date not null,calculation text not null check(calculation in ('fixed','quantity','hours')),quantity numeric(16,4) not null default 0 check(quantity>=0),rate numeric(16,4) not null default 0 check(rate>=0),fixed_amount numeric(16,4) not null default 0 check(fixed_amount>=0),notes text not null default '',sort_order integer not null);
create table public.adjustments(id uuid primary key default gen_random_uuid(),record_id uuid not null references public.monthly_records on delete cascade,kind text not null check(kind in ('bonus','reimbursement','allowance','commission','deduction','correction','other')),description text not null check(length(description) between 1 and 500),amount numeric(16,4) not null check(kind='correction' or amount>=0),notes text not null default '',sort_order integer not null);
create table public.payments(id uuid primary key default gen_random_uuid(),record_id uuid not null references public.monthly_records,request_id uuid not null unique,receipt_number text not null unique,payment_date date not null,amount numeric(16,2) not null check(amount>0),method text not null check(method in ('bank_transfer','cash','card','wallet','other')),reference text not null check(length(reference)>0),paying_account text not null default '',notes text not null default '',remaining_balance numeric(16,2) not null check(remaining_balance>=0),proof_path text unique,created_by uuid not null references public.profiles,created_at timestamptz not null default now(),reversed_at timestamptz,reversed_by uuid references public.profiles,reversal_reason text);
create table public.documents(id uuid primary key default gen_random_uuid(),record_id uuid not null references public.monthly_records,payment_id uuid references public.payments,kind text not null check(kind in ('statement','receipt')),document_number text not null,version integer not null,storage_path text not null unique,state text not null default 'pending' check(state in ('pending','ready')),snapshot jsonb not null,created_by uuid not null references public.profiles,created_at timestamptz not null default now(),unique(document_number,version));
create table public.document_versions(id uuid primary key default gen_random_uuid(),document_id uuid not null unique references public.documents,sha256 text not null check(length(sha256)=64),bytes integer not null check(bytes>0),created_at timestamptz not null default now());
create table public.audit_logs(id uuid primary key default gen_random_uuid(),actor_id uuid references public.profiles,actor_name text not null,action text not null,object_id uuid not null,record_id uuid references public.monthly_records,before_state jsonb,after_state jsonb,created_at timestamptz not null default now());
create index records_period_idx on public.monthly_records(period,status);
create index personnel_name_idx on public.personnel(lower(legal_name));
create index work_record_idx on public.work_items(record_id);
create index adjustment_record_idx on public.adjustments(record_id);
create index payment_record_idx on public.payments(record_id);
create index document_record_idx on public.documents(record_id);
create index audit_record_idx on public.audit_logs(record_id,created_at desc);

create function private.role() returns text language sql stable security definer set search_path='' as $$select role::text from public.profiles where id=auth.uid() and active$$;
create function private.require_roles(roles text[]) returns void language plpgsql security definer set search_path='' as $$begin if coalesce(private.role(),'')<>all(roles) then raise exception 'Permission denied.' using errcode='42501';end if;end$$;
create function private.audit(action text,obj uuid,rec uuid,old_value jsonb,new_value jsonb) returns void language sql security definer set search_path='' as $$insert into public.audit_logs(actor_id,actor_name,action,object_id,record_id,before_state,after_state) select auth.uid(),coalesce((select full_name from public.profiles where id=auth.uid()),'System'),action,obj,rec,old_value,new_value$$;
create function private.scale(currency text) returns integer language sql immutable as $$select case when currency in ('JPY','KRW') then 0 else 2 end$$;
create function private.person(person_id uuid) returns jsonb language sql stable security definer set search_path='' as $$select to_jsonb(p)||jsonb_build_object('department',d.name,'default_rate',p.default_rate::text) from public.personnel p join public.departments d on d.id=p.department_id where p.id=person_id$$;
create function private.totals(rec uuid) returns jsonb language sql stable security definer set search_path='' as $$
 with r as(select currency from public.monthly_records where id=rec),w as(select coalesce(sum(round(case when calculation='fixed' then fixed_amount else quantity*rate end,private.scale(r.currency))),0) n from public.work_items cross join r where record_id=rec),a as(select coalesce(sum(case when kind not in ('reimbursement','deduction') then amount else 0 end),0) additional,coalesce(sum(case when kind='reimbursement' then amount else 0 end),0) reimbursements,coalesce(sum(case when kind='deduction' then amount else 0 end),0) deductions from public.adjustments where record_id=rec),p as(select coalesce(sum(amount),0) paid from public.payments where record_id=rec and reversed_at is null)
 select jsonb_build_object('work_subtotal',w.n::text,'additional',a.additional::text,'reimbursements',a.reimbursements::text,'deductions',a.deductions::text,'total',(w.n+a.additional+a.reimbursements-a.deductions)::text,'paid',p.paid::text,'balance',(w.n+a.additional+a.reimbursements-a.deductions-p.paid)::text) from w,a,p$$;
create function private.record_json(rec uuid) returns jsonb language sql stable security definer set search_path='' as $$select to_jsonb(r)||private.totals(r.id) from public.monthly_records r where id=rec$$;
create function private.items_json(rec uuid) returns jsonb language sql stable security definer set search_path='' as $$select coalesce(jsonb_agg(to_jsonb(w)||jsonb_build_object('quantity',w.quantity::text,'rate',w.rate::text,'fixed_amount',w.fixed_amount::text,'amount',round(case when calculation='fixed' then w.fixed_amount else w.quantity*w.rate end,private.scale(r.currency))::text,'project',p.name) order by w.sort_order),'[]') from public.work_items w join public.monthly_records r on r.id=w.record_id left join public.projects p on p.id=w.project_id where record_id=rec$$;
create function private.adjustments_json(rec uuid) returns jsonb language sql stable security definer set search_path='' as $$select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('amount',a.amount::text) order by a.sort_order),'[]') from public.adjustments a where record_id=rec$$;
create function private.payments_json(rec uuid default null) returns jsonb language sql stable security definer set search_path='' as $$select coalesce(jsonb_agg(to_jsonb(p)||jsonb_build_object('amount',amount::text,'remaining_balance',remaining_balance::text) order by payment_date desc,created_at desc),'[]') from public.payments p where (rec is null or record_id=rec) and private.role() in ('super_admin','finance')$$;

-- RLS applies to direct REST access as well as application endpoints. The private
-- schema is not exposed through PostgREST. Mutation functions check the actor again.
do $$declare t text;begin foreach t in array array['profiles','departments','projects','personnel','personnel_payment_details','monthly_records','work_items','adjustments','payments','documents','document_versions','audit_logs'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from anon, authenticated',t);execute format('grant select on public.%I to authenticated',t);end loop;end$$;
grant usage on schema private to authenticated;
grant execute on function private.role() to authenticated;
create policy profiles_read on public.profiles for select to authenticated using(id=auth.uid() or private.role()='super_admin');
do $$declare t text;begin foreach t in array array['departments','projects','personnel','monthly_records','work_items','adjustments'] loop execute format('create policy member_read on public.%I for select to authenticated using(private.role() is not null)',t);end loop;end$$;
do $$declare t text;begin foreach t in array array['personnel_payment_details','payments','documents','document_versions','audit_logs'] loop execute format('create policy finance_read on public.%I for select to authenticated using(private.role() in (''super_admin'',''finance''))',t);end loop;end$$;

create function public.workspace_data() returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform private.require_roles(array['super_admin','finance','manager','viewer']);
 return jsonb_build_object('profile',(select to_jsonb(p) from public.profiles p where id=auth.uid()),'personnel',(select coalesce(jsonb_agg(private.person(id) order by personnel_code),'[]') from public.personnel),'departments',(select coalesce(jsonb_agg(d order by name),'[]') from public.departments d),'projects',(select coalesce(jsonb_agg(p order by name),'[]') from public.projects p),'records',(select coalesce(jsonb_agg(private.record_json(id) order by period desc,created_at desc),'[]') from public.monthly_records),'payments',private.payments_json(),'documents',(select coalesce(jsonb_agg(to_jsonb(d)-'snapshot' order by created_at desc),'[]') from public.documents d where private.role() in ('super_admin','finance') and state='ready'),'activity',(select coalesce(jsonb_agg(a order by created_at desc),'[]') from (select id,actor_name,action,object_id,record_id,created_at from public.audit_logs where private.role() in ('super_admin','finance') order by created_at desc limit 100) a),'profiles',(select coalesce(jsonb_agg(p),'[]') from public.profiles p where private.role()='super_admin'));
end$$;
create function public.record_detail(record_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$begin
 perform private.require_roles(array['super_admin','finance','manager','viewer']);
 if not exists(select 1 from public.monthly_records where id=record_id) then raise exception 'Record not found.';end if;
 return jsonb_build_object('record',private.record_json(record_id),'items',private.items_json(record_id),'adjustments',private.adjustments_json(record_id),'payments',private.payments_json(record_id),'documents',(select coalesce(jsonb_agg(to_jsonb(d)-'snapshot' order by created_at desc),'[]') from public.documents d where d.record_id=record_detail.record_id and state='ready' and private.role() in ('super_admin','finance')),'activity',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'actor_name',actor_name,'action',action,'object_id',object_id,'record_id',a.record_id,'created_at',created_at) order by created_at desc),'[]') from public.audit_logs a where a.record_id=record_detail.record_id and (private.role() in ('super_admin','finance') or action like 'Statement %')));
end$$;

create function public.save_personnel(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare person_id uuid;old_value jsonb;v public.personnel;begin
 perform private.require_roles(array['super_admin','finance']);
 person_id=(input->>'id')::uuid;
 if person_id is not null then select * into v from public.personnel where id=person_id for update;if not found then raise exception 'Personnel not found.';end if;if v.version<>(input->>'expected_version')::integer then raise exception 'This profile changed. Reload and try again.' using errcode='40001';end if;old_value=private.person(person_id);end if;
 if person_id is null then insert into public.personnel(legal_name,display_name,engagement,department_id,position,email,phone,start_date,status,currency,default_rate,payment_structure,notes) values(trim(input->>'legal_name'),input->>'display_name',input->>'engagement',(input->>'department_id')::uuid,input->>'position',input->>'email',input->>'phone',(input->>'start_date')::date,input->>'status',input->>'currency',(input->>'default_rate')::numeric,input->>'payment_structure',input->>'notes') returning id into person_id;
 else update public.personnel set legal_name=trim(input->>'legal_name'),display_name=input->>'display_name',engagement=input->>'engagement',department_id=(input->>'department_id')::uuid,position=input->>'position',email=input->>'email',phone=input->>'phone',start_date=(input->>'start_date')::date,status=input->>'status',currency=input->>'currency',default_rate=(input->>'default_rate')::numeric,payment_structure=input->>'payment_structure',notes=input->>'notes',version=version+1 where id=person_id;end if;
 if input ? 'payment_info' then insert into public.personnel_payment_details values(person_id,input->>'payment_info') on conflict(personnel_id) do update set payment_info=excluded.payment_info;perform private.audit('Personnel payment details changed',person_id,null,null,jsonb_build_object('updated',true));end if;
 perform private.audit(case when old_value is null then 'Personnel created' else 'Personnel details changed' end,person_id,null,old_value,private.person(person_id));return jsonb_build_object('id',person_id);
end$$;

create function public.save_record(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare rec uuid;old_value jsonb;r public.monthly_records;p public.personnel;i jsonb;idx integer:=0;amount numeric;s integer;begin
 perform private.require_roles(array['super_admin','finance','manager']);
 rec=(input->>'id')::uuid;
 if jsonb_array_length(input->'items') not between 1 and 100 or jsonb_array_length(input->'adjustments')>100 then raise exception 'Include 1–100 work items and at most 100 adjustments.';end if;
 if rec is null then
  select id into rec from public.monthly_records where request_id=(input->>'request_id')::uuid;if found then return jsonb_build_object('id',rec);end if;
  select * into strict p from public.personnel where id=(input->>'personnel_id')::uuid;if p.status<>'active' then raise exception 'Only active personnel may receive new records.';end if;
  insert into public.monthly_records(request_id,statement_number,personnel_id,period,currency,notes,created_by) values((input->>'request_id')::uuid,'AS-MWS-'||to_char((input->>'period')::date,'YYYY-MM')||'-'||private.next_number('private.statement_number',6),p.id,(input->>'period')::date,p.currency,input->>'notes',auth.uid()) returning * into r;rec=r.id;
 else
  select * into strict r from public.monthly_records where id=rec for update;
  if r.status<>'draft' then raise exception 'Only draft records can be edited. Request a revision first.';end if;
  if r.version<>(input->>'expected_version')::integer then raise exception 'This statement changed. Reload and try again.' using errcode='40001';end if;
  if r.personnel_id<>(input->>'personnel_id')::uuid or r.period<>(input->>'period')::date then raise exception 'Personnel and reporting period cannot change.';end if;
  old_value=jsonb_build_object('record',private.record_json(rec),'items',private.items_json(rec),'adjustments',private.adjustments_json(rec));
  delete from public.work_items where record_id=rec;delete from public.adjustments where record_id=rec;
  update public.monthly_records set notes=input->>'notes',version=version+1 where id=rec;
 end if;
 s=private.scale(r.currency);
 for i in select * from jsonb_array_elements(input->'items') loop
  if (i->>'completed_on')::date<r.period or (i->>'completed_on')::date>=r.period+interval '1 month' then raise exception 'Completion dates must fall within the reporting month.';end if;
  if i->>'calculation'<>'fixed' and (i->>'quantity')::numeric<=0 then raise exception 'Hours or quantity must be greater than zero.';end if;
  if i->>'calculation'='fixed' and (i->>'fixed_amount')::numeric<>round((i->>'fixed_amount')::numeric,s) then raise exception 'Fixed amounts must use the currency precision.';end if;
  insert into public.work_items(record_id,title,description,project_id,completed_on,calculation,quantity,rate,fixed_amount,notes,sort_order) values(rec,i->>'title',i->>'description',(i->>'project_id')::uuid,(i->>'completed_on')::date,i->>'calculation',(i->>'quantity')::numeric,(i->>'rate')::numeric,(i->>'fixed_amount')::numeric,i->>'notes',idx);idx=idx+1;
 end loop;
 idx=0;for i in select * from jsonb_array_elements(input->'adjustments') loop
  amount=(i->>'amount')::numeric;if amount<>round(amount,s) then raise exception 'Adjustment amounts must use the currency precision.';end if;
  insert into public.adjustments(record_id,kind,description,amount,notes,sort_order) values(rec,i->>'kind',i->>'description',amount,i->>'notes',idx);idx=idx+1;
 end loop;
 if (private.totals(rec)->>'total')::numeric<0 then raise exception 'Total payable cannot be negative.';end if;
 perform private.audit(case when old_value is null then 'Statement created' else 'Statement edited' end,rec,rec,old_value,jsonb_build_object('record',private.record_json(rec),'items',private.items_json(rec),'adjustments',private.adjustments_json(rec)));return jsonb_build_object('id',rec);
end$$;

create function public.transition_record(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare r public.monthly_records;target public.record_status;old_value jsonb;begin
 perform private.require_roles(array['super_admin','finance','manager']);select * into strict r from public.monthly_records where id=(input->>'id')::uuid for update;target=(input->>'status')::public.record_status;
 if r.version<>(input->>'expected_version')::integer then raise exception 'This statement changed. Reload and try again.' using errcode='40001';end if;old_value=private.record_json(r.id);
 if target='submitted' and r.status='draft' then
  if not exists(select 1 from public.work_items where record_id=r.id) then raise exception 'Add at least one work item.';end if;
 elsif target='approved' and r.status='submitted' then
  perform private.require_roles(array['super_admin','finance']);
  update public.monthly_records set snapshot=private.person(r.personnel_id),approved_by=auth.uid(),approved_by_name=(select full_name from public.profiles where id=auth.uid()),approved_at=now() where id=r.id;
 elsif target='awaiting_payment' and r.status='approved' then perform private.require_roles(array['super_admin','finance']);if (private.totals(r.id)->>'total')::numeric=0 then target='paid';end if;
 elsif target='archived' and r.status='paid' then perform private.require_roles(array['super_admin','finance']);
 elsif target='draft' and r.status in ('submitted','approved','awaiting_payment') then
  if r.status<>'submitted' then perform private.require_roles(array['super_admin','finance']);end if;
  if length(trim(coalesce(input->>'reason','')))<10 then raise exception 'Give a revision reason of at least 10 characters.';end if;
  if exists(select 1 from public.payments where record_id=r.id and reversed_at is null) then raise exception 'Reverse existing payments before revising this statement.';end if;
  update public.monthly_records set snapshot=null,approved_by=null,approved_by_name=null,approved_at=null where id=r.id;
 else raise exception 'This workflow transition is not allowed.';end if;
 update public.monthly_records set status=target,version=version+1 where id=r.id;
 perform private.audit('Statement '||target::text,r.id,r.id,old_value,private.record_json(r.id)||jsonb_build_object('reason',input->>'reason'));return jsonb_build_object('id',r.id);
end$$;

create function public.record_payment(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare r public.monthly_records;payment public.payments;amount numeric;balance numeric;begin
 perform private.require_roles(array['super_admin','finance']);
 select * into strict r from public.monthly_records where id=(input->>'record_id')::uuid for update;
 select * into payment from public.payments where request_id=(input->>'request_id')::uuid;if found then if payment.record_id<>r.id or payment.amount<>(input->>'amount')::numeric or payment.reference<>input->>'reference' or payment.payment_date<>(input->>'payment_date')::date or payment.method<>input->>'method' or payment.paying_account<>input->>'paying_account' or payment.notes<>input->>'notes' then raise exception 'Request identifier was already used for a different payment.';end if;return jsonb_build_object('id',payment.id,'record_id',r.id);end if;
 if r.status not in ('approved','awaiting_payment') then raise exception 'Only approved or awaiting-payment statements accept payments.';end if;
 amount=(input->>'amount')::numeric;balance=(private.totals(r.id)->>'balance')::numeric;
 if amount<=0 or amount>balance or amount<>round(amount,private.scale(r.currency)) then raise exception 'Payment must be positive, within the remaining balance, and use the currency precision.';end if;
 if (input->>'payment_date')::date>current_date then raise exception 'A payment date cannot be in the future.';end if;
 insert into public.payments(record_id,request_id,receipt_number,payment_date,amount,method,reference,paying_account,notes,remaining_balance,created_by) values(r.id,(input->>'request_id')::uuid,'AS-PR-'||to_char(r.period,'YYYY-MM')||'-'||private.next_number('private.receipt_number',6),(input->>'payment_date')::date,amount,input->>'method',input->>'reference',input->>'paying_account',input->>'notes',balance-amount,auth.uid()) returning * into payment;
 update public.monthly_records set status=case when balance-amount=0 then 'paid'::public.record_status else 'awaiting_payment'::public.record_status end,version=version+1 where id=r.id;
 perform private.audit('Payment recorded',payment.id,r.id,null,to_jsonb(payment)||jsonb_build_object('amount',amount::text));return jsonb_build_object('id',payment.id,'record_id',r.id);
end$$;
create function public.reverse_payment(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare p public.payments;r public.monthly_records;begin
 perform private.require_roles(array['super_admin','finance']);select * into strict p from public.payments where id=(input->>'id')::uuid;select * into strict r from public.monthly_records where id=p.record_id for update;select * into strict p from public.payments where id=p.id for update;
 if p.reversed_at is not null then raise exception 'Payment is already reversed.';end if;
 if length(trim(input->>'reason'))<10 then raise exception 'Give a correction reason of at least 10 characters.';end if;
 update public.payments set reversed_at=now(),reversed_by=auth.uid(),reversal_reason=input->>'reason' where id=p.id;
 update public.monthly_records set status='awaiting_payment',version=version+1 where id=p.record_id;
 perform private.audit('Payment reversed',p.id,p.record_id,to_jsonb(p),jsonb_build_object('reason',input->>'reason'));return jsonb_build_object('id',p.id,'record_id',p.record_id);
end$$;

create function public.save_directory(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare obj uuid;old_value jsonb;new_value jsonb;begin
 perform private.require_roles(array['super_admin','finance']);obj=(input->>'id')::uuid;
 if input->>'kind'='department' then
  if obj is null then insert into public.departments(name) values(trim(input->>'name')) returning id into obj;else select to_jsonb(d) into old_value from public.departments d where id=obj for update;if not found then raise exception 'Department not found.';end if;update public.departments set name=trim(input->>'name') where id=obj;end if;select to_jsonb(d) into new_value from public.departments d where id=obj;
 elsif input->>'kind'='project' then
  if obj is null then insert into public.projects(name,status) values(trim(input->>'name'),input->>'status') returning id into obj;else select to_jsonb(p) into old_value from public.projects p where id=obj for update;if not found then raise exception 'Project not found.';end if;update public.projects set name=trim(input->>'name'),status=input->>'status' where id=obj;end if;select to_jsonb(p) into new_value from public.projects p where id=obj;
 else raise exception 'Unknown directory.';end if;
 perform private.audit(initcap(input->>'kind')||' saved',obj,null,old_value,new_value);return jsonb_build_object('id',obj);
end$$;
create function public.save_profile(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare obj uuid;old_value jsonb;begin
 perform private.require_roles(array['super_admin']);perform pg_advisory_xact_lock(20260916);
 obj=(input->>'id')::uuid;select to_jsonb(p) into old_value from public.profiles p where id=obj for update;
 if obj=auth.uid() and (input->>'role'<>'super_admin' or not (input->>'active')::boolean) then raise exception 'You cannot remove your own administrative access.';end if;
 insert into public.profiles(id,full_name,role,active) values(obj,input->>'full_name',(input->>'role')::public.app_role,(input->>'active')::boolean) on conflict(id) do update set full_name=excluded.full_name,role=excluded.role,active=excluded.active;
 perform private.audit('User access changed',obj,null,old_value,input);return jsonb_build_object('id',obj);
end$$;

create function public.reserve_document(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare r public.monthly_records;p public.payments;d public.documents;n text;v integer;snap jsonb;doc_id uuid:=gen_random_uuid();begin
 perform private.require_roles(array['super_admin','finance']);select * into strict r from public.monthly_records where id=(input->>'record_id')::uuid for update;
 if r.status not in ('approved','awaiting_payment','paid','archived') then raise exception 'Approve the statement before issuing a document.';end if;
 if input->>'kind'='receipt' then select * into strict p from public.payments where id=(input->>'payment_id')::uuid and record_id=r.id;if p.reversed_at is not null then raise exception 'A reversed payment cannot receive a new receipt.';end if;n=p.receipt_number;
 elsif input->>'kind'='statement' then n=r.statement_number;else raise exception 'Unknown document type.';end if;
 -- Reuse any pending reservation, preserving its historical snapshot after failure.
 select * into d from public.documents where document_number=n and state='pending' and (snapshot->'record'->>'version')::integer=r.version order by version desc limit 1;if found then return to_jsonb(d);end if;
 select coalesce(max(version),0)+1 into v from public.documents where document_number=n;
 snap=jsonb_build_object('personnel',r.snapshot,'record',private.record_json(r.id),'items',private.items_json(r.id),'adjustments',private.adjustments_json(r.id),'payment',case when p.id is null then null else to_jsonb(p)||jsonb_build_object('amount',p.amount::text,'remaining_balance',p.remaining_balance::text) end,'issued_at',now());
 insert into public.documents(id,record_id,payment_id,kind,document_number,version,storage_path,snapshot,created_by) values(doc_id,r.id,p.id,input->>'kind',n,v,'personnel/'||r.personnel_id||'/'||to_char(r.period,'YYYY/MM')||'/'||(input->>'kind')||'-'||doc_id||'.pdf',snap,auth.uid()) returning * into d;
 return to_jsonb(d);
end$$;
create function public.finalize_document(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare d public.documents;begin
 perform private.require_roles(array['super_admin','finance']);select * into strict d from public.documents where id=(input->>'id')::uuid for update;
 if d.state='ready' then return jsonb_build_object('id',d.id);end if;
 if not exists(select 1 from storage.objects where bucket_id='financial-documents' and name=d.storage_path) then raise exception 'Document upload is missing.';end if;
 insert into public.document_versions(document_id,sha256,bytes) values(d.id,input->>'sha256',(input->>'bytes')::integer);update public.documents set state='ready' where id=d.id;
 perform private.audit(case when d.kind='receipt' then 'Receipt generated' else 'Statement PDF generated' end,d.id,d.record_id,null,jsonb_build_object('document_number',d.document_number,'version',d.version));return jsonb_build_object('id',d.id);
end$$;
create function public.attach_proof(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare p public.payments;begin
 perform private.require_roles(array['super_admin','finance']);select * into strict p from public.payments where id=(input->>'id')::uuid for update;
 if p.proof_path is not null then raise exception 'A proof is already attached.';end if;
 if input->>'path'<>'proofs/'||p.id||'/'||(input->>'filename') or input->>'filename' !~ '^[a-f0-9-]+\.(pdf|png|jpg)$' then raise exception 'Invalid proof path.';end if;
 if not exists(select 1 from storage.objects where bucket_id='payment-proofs' and name=input->>'path') then raise exception 'Proof upload is missing.';end if;
 update public.payments set proof_path=input->>'path' where id=p.id;perform private.audit('Payment proof attached',p.id,p.record_id,null,jsonb_build_object('attached',true));return jsonb_build_object('id',p.id);
end$$;

-- Revoke default function access, including internal SECURITY DEFINER helpers.
revoke all on all functions in schema private from public,anon,authenticated;
grant execute on function private.role() to authenticated;
revoke all on all functions in schema public from public,anon;
grant execute on function public.workspace_data(),public.record_detail(uuid),public.save_personnel(jsonb),public.save_record(jsonb),public.transition_record(jsonb),public.record_payment(jsonb),public.reverse_payment(jsonb),public.save_directory(jsonb),public.save_profile(jsonb),public.reserve_document(jsonb),public.finalize_document(jsonb),public.attach_proof(jsonb) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('financial-documents','financial-documents',false,5242880,array['application/pdf']),('payment-proofs','payment-proofs',false,5242880,array['application/pdf','image/png','image/jpeg']);
create policy finance_documents_read on storage.objects for select to authenticated using(bucket_id='financial-documents' and private.role() in ('super_admin','finance') and exists(select 1 from public.documents d where d.storage_path=name));
create policy finance_documents_insert on storage.objects for insert to authenticated with check(bucket_id='financial-documents' and private.role() in ('super_admin','finance') and exists(select 1 from public.documents d where d.storage_path=name and d.state='pending' and d.created_by=auth.uid()));
create policy finance_proofs_read on storage.objects for select to authenticated using(bucket_id='payment-proofs' and private.role() in ('super_admin','finance'));
create policy finance_proofs_insert on storage.objects for insert to authenticated with check(bucket_id='payment-proofs' and private.role() in ('super_admin','finance') and name ~ '^proofs/[a-f0-9-]+/[a-f0-9-]+\.(pdf|png|jpg)$' and exists(select 1 from public.payments p where p.id::text=split_part(name,'/',2) and p.proof_path is null));
