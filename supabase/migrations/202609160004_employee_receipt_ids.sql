-- Existing records and issued documents retain their historical identifiers.
begin;
alter table public.departments add column code text;
alter table public.departments add constraint department_code_format check(code is null or code ~ '^[A-Z]{2}$');
alter table public.departments add constraint department_code_unique unique(code);
update public.departments set code='GD' where id=(select id from public.departments where lower(trim(name)) in ('game development','game dev') order by name limit 1);
alter table public.personnel alter column personnel_code drop default;
create function private.validate_employee_id() returns trigger language plpgsql set search_path='' as $$begin
 if new.personnel_code !~ '^[0-9]{7}$' then raise exception 'Employee ID must contain seven digits: YYZZSSS.';end if;
 if left(new.personnel_code,2) <> to_char(new.start_date,'YY') then raise exception 'The first two digits of the employee ID must match the year of hire.';end if;
 return new;end$$;
create trigger employee_id_format before insert or update of personnel_code,start_date on public.personnel for each row execute function private.validate_employee_id();
create table private.receipt_counters(department_code text not null,payment_date date not null,last_number integer not null check(last_number>0),primary key(department_code,payment_date));
revoke all on private.receipt_counters from public,anon,authenticated;
create function private.next_receipt_number(rec uuid,paid_on date) returns text language plpgsql security definer set search_path='' as $$declare dept_code text;seq integer;begin
 select coalesce(nullif(r.snapshot->>'department_code',''),d.code) into dept_code from public.monthly_records r join public.departments d on d.id=coalesce(nullif(r.snapshot->>'department_id','')::uuid,(select p.department_id from public.personnel p where p.id=r.personnel_id)) where r.id=rec;
 if dept_code is null then raise exception 'Set this department’s two-letter receipt code in Administration before recording payment.';end if;
 insert into private.receipt_counters values(dept_code,paid_on,1) on conflict(department_code,payment_date) do update set last_number=private.receipt_counters.last_number+1 returning last_number into seq;
 return 'AS'||dept_code||'-'||to_char(paid_on,'YYMMDD')||'-'||lpad(seq::text,greatest(3,length(seq::text)),'0');
end$$;
create or replace function private.person(person_id uuid) returns jsonb language sql stable security definer set search_path='' as $$select to_jsonb(p)||jsonb_build_object('department',d.name,'department_code',d.code,'default_rate',p.default_rate::text) from public.personnel p join public.departments d on d.id=p.department_id where p.id=person_id$$;
create or replace function public.save_personnel(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare person_id uuid;old_value jsonb;v public.personnel;begin
 perform private.require_roles(array['super_admin','finance']);
 person_id=(input->>'id')::uuid;
 if person_id is not null then select * into v from public.personnel where id=person_id for update;if not found then raise exception 'Personnel not found.';end if;if v.version<>(input->>'expected_version')::integer then raise exception 'This profile changed. Reload and try again.' using errcode='40001';end if;old_value=private.person(person_id);end if;
 if person_id is null then insert into public.personnel(personnel_code,legal_name,display_name,engagement,department_id,position,email,phone,start_date,status,currency,default_rate,payment_structure,notes) values(input->>'personnel_code',trim(input->>'legal_name'),input->>'display_name',input->>'engagement',(input->>'department_id')::uuid,input->>'position',input->>'email',input->>'phone',(input->>'start_date')::date,input->>'status',input->>'currency',(input->>'default_rate')::numeric,input->>'payment_structure',input->>'notes') returning id into person_id;
 else update public.personnel set personnel_code=input->>'personnel_code',legal_name=trim(input->>'legal_name'),display_name=input->>'display_name',engagement=input->>'engagement',department_id=(input->>'department_id')::uuid,position=input->>'position',email=input->>'email',phone=input->>'phone',start_date=(input->>'start_date')::date,status=input->>'status',currency=input->>'currency',default_rate=(input->>'default_rate')::numeric,payment_structure=input->>'payment_structure',notes=input->>'notes',version=version+1 where id=person_id;end if;
 if input ? 'payment_info' then insert into public.personnel_payment_details values(person_id,input->>'payment_info') on conflict(personnel_id) do update set payment_info=excluded.payment_info;perform private.audit('Personnel payment details changed',person_id,null,null,jsonb_build_object('updated',true));end if;
 perform private.audit(case when old_value is null then 'Personnel created' else 'Personnel details changed' end,person_id,null,old_value,private.person(person_id));return jsonb_build_object('id',person_id);
end$$;
create or replace function public.save_directory(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare obj uuid;old_value jsonb;new_value jsonb;begin
 perform private.require_roles(array['super_admin','finance']);obj=(input->>'id')::uuid;
 if input->>'kind'='department' then
  if coalesce(upper(trim(input->>'code')),'') !~ '^[A-Z]{2}$' then raise exception 'Enter a two-letter department code, such as GD.';end if;
  if obj is null then insert into public.departments(name,code) values(trim(input->>'name'),upper(trim(input->>'code'))) returning id into obj;else select to_jsonb(d) into old_value from public.departments d where id=obj for update;if not found then raise exception 'Department not found.';end if;update public.departments set name=trim(input->>'name'),code=upper(trim(input->>'code')) where id=obj;end if;select to_jsonb(d) into new_value from public.departments d where id=obj;
 elsif input->>'kind'='project' then
  if obj is null then insert into public.projects(name,status) values(trim(input->>'name'),input->>'status') returning id into obj;else select to_jsonb(p) into old_value from public.projects p where id=obj for update;if not found then raise exception 'Project not found.';end if;update public.projects set name=trim(input->>'name'),status=input->>'status' where id=obj;end if;select to_jsonb(p) into new_value from public.projects p where id=obj;
 else raise exception 'Unknown directory.';end if;
 perform private.audit(initcap(input->>'kind')||' saved',obj,null,old_value,new_value);return jsonb_build_object('id',obj);
end$$;
create or replace function public.record_payment(input jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare r public.monthly_records;payment public.payments;amount numeric;balance numeric;begin
 perform private.require_roles(array['super_admin','finance']);
 select * into strict r from public.monthly_records where id=(input->>'record_id')::uuid for update;
 select * into payment from public.payments where request_id=(input->>'request_id')::uuid;if found then if payment.record_id<>r.id or payment.amount<>(input->>'amount')::numeric or payment.reference<>input->>'reference' or payment.payment_date<>(input->>'payment_date')::date or payment.method<>input->>'method' or payment.paying_account<>input->>'paying_account' or payment.notes<>input->>'notes' then raise exception 'Request identifier was already used for a different payment.';end if;return jsonb_build_object('id',payment.id,'record_id',r.id);end if;
 if r.status not in ('approved','awaiting_payment') then raise exception 'Only approved or awaiting-payment statements accept payments.';end if;
 amount=(input->>'amount')::numeric;balance=(private.totals(r.id)->>'balance')::numeric;
 if amount<=0 or amount>balance or amount<>round(amount,private.scale(r.currency)) then raise exception 'Payment must be positive, within the remaining balance, and use the currency precision.';end if;
 if (input->>'payment_date')::date>current_date then raise exception 'A payment date cannot be in the future.';end if;
 insert into public.payments(record_id,request_id,receipt_number,payment_date,amount,method,reference,paying_account,notes,remaining_balance,created_by) values(r.id,(input->>'request_id')::uuid,private.next_receipt_number(r.id,(input->>'payment_date')::date),(input->>'payment_date')::date,amount,input->>'method',input->>'reference',input->>'paying_account',input->>'notes',balance-amount,auth.uid()) returning * into payment;
 update public.monthly_records set status=case when balance-amount=0 then 'paid'::public.record_status else 'awaiting_payment'::public.record_status end,version=version+1 where id=r.id;
 perform private.audit('Payment recorded',payment.id,r.id,null,to_jsonb(payment)||jsonb_build_object('amount',amount::text));return jsonb_build_object('id',payment.id,'record_id',r.id);
end$$;
revoke all on function private.validate_employee_id(),private.next_receipt_number(uuid,date) from public,anon,authenticated;
commit;
