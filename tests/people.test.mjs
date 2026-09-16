import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
const db=new PGlite();
const ids={admin:'00000000-0000-4000-8000-000000000001',finance:'00000000-0000-4000-8000-000000000002',manager:'00000000-0000-4000-8000-000000000003',viewer:'00000000-0000-4000-8000-000000000004'};
async function actor(role='finance'){await db.exec('reset role');await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({amr:[{method:'oauth'}]})]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids[role]||'']);await db.exec('set role '+(role==='anon'?'anon':'authenticated'));}
async function rpc(name,input){const r=await db.query(`select public.${name}(${input===undefined?'':'$1::jsonb'}) as result`,input===undefined?[]:[JSON.stringify(input)]);return r.rows[0].result;}
let person,record,department;
const item={title:'Production work',description:'Reviewed delivery',project_id:null,completed_on:'2026-08-17',calculation:'hours',quantity:'3.3333',rate:'10.1250',fixed_amount:'0',notes:''};
before(async()=>{await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);create table auth.identities(user_id uuid,provider text,identity_data jsonb);create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant select,insert on storage.objects to authenticated;`);for(const migration of ['202609160001_operations.sql','202609160002_reports.sql','202609160003_payment_details.sql','202609160004_employee_receipt_ids.sql','202609160005_google_workspace_access.sql','202609160006_employee_role.sql','202609160007_people_hub.sql'])await db.exec(await readFile(new URL('../supabase/migrations/'+migration,import.meta.url),'utf8'));for(const [role,id] of Object.entries(ids)){await db.query('insert into auth.users values($1,$2,now())',[id,role+'@aerinyustudios.com']);await db.query('insert into auth.identities values($1,$2,$3)',[id,'google',JSON.stringify({email:role+'@aerinyustudios.com',email_verified:true,custom_claims:{hd:'aerinyustudios.com'}})]);await db.query('insert into public.profiles(id,full_name,role) values($1,$2,$3)',[id,role,role==='admin'?'super_admin':role]);}await actor();});
after(()=>db.close());
const hire={request_id:'11111111-1111-4111-8111-111111111111',given_name:'New',family_name:'Employee',legal_name:'New Employee',display_name:'New',email:'nemployee@aerinyustudios.com',engagement:'employee',position:'Developer',team:'Production',start_date:'2026-09-01',currency:'MYR',personal_email:'personal@example.test',phone:'123',date_of_birth:'1999-01-01',residential_address:'Private home',country_of_residence:'Malaysia',manager_id:null};
let employee,second,claim;
test('automatic IDs begin at sequence 011 and retries preserve the record and ID',async()=>{
 await actor('admin');const d=await rpc('save_directory',{kind:'department',id:null,name:'Game Development',code:'GD',status:'active'});hire.department_id=d.id;
 employee=(await rpc('onboard_employee',hire)).id;
 assert.equal((await rpc('onboard_employee',hire)).id,employee);
 const data=await rpc('people_directory');assert.equal(data.people.length,1);assert.match(data.people[0].personnel_code,/^26[0-9]{2}011$/);assert.equal(data.next_sequence,12);
 second=(await rpc('onboard_employee',{...hire,request_id:crypto.randomUUID(),email:'second@aerinyustudios.com',legal_name:'Second Person',manager_id:employee})).id;
 assert.match((await rpc('people_directory')).people.find(p=>p.id===second).personnel_code,/^26[0-9]{2}012$/);
 await assert.rejects(()=>rpc('onboard_employee',{...hire,request_id:crypto.randomUUID()}),/already assigned/);
 await actor('finance');await assert.rejects(()=>rpc('onboard_employee',{...hire,request_id:crypto.randomUUID(),email:'blocked@aerinyustudios.com'}),/Permission denied/);
});
test('department management prevents reporting cycles and stale edits',async()=>{
 await actor('admin');const e=(await db.query('select public.employee_detail($1) as r',[employee])).rows[0].r.employment;
 await assert.rejects(()=>rpc('update_employee',{...e,id:employee,expected_version:e.version,manager_id:second}),/cycle/);
 await rpc('update_employee',{...e,id:employee,expected_version:e.version,manager_id:null,team:'Engineering'});
 await assert.rejects(()=>rpc('update_employee',{...e,id:employee,expected_version:e.version,manager_id:null}),/Reload/);
 await rpc('set_department_head',{id:hire.department_id,head_id:employee});
 assert.equal((await rpc('people_directory')).departments[0].head_id,employee);
});
test('account setup has a lease, supports retries and creates employee-only app access',async()=>{
 await actor('admin');claim=(await db.query('select public.claim_workspace_account($1) as r',[employee])).rows[0].r;
 await assert.rejects(()=>db.query('select public.claim_workspace_account($1)',[employee]),/already in progress/);
 await rpc('fail_workspace_account',{personnel_id:employee,claim_token:claim.claim_token,message:'Retryable connection failure'});
 claim=(await db.query('select public.claim_workspace_account($1) as r',[employee])).rows[0].r;
 ids.employee='00000000-0000-4000-8000-000000000005';
 await db.exec('reset role');await db.query('insert into auth.users values($1,$2,now())',[ids.employee,hire.email]);await db.query('insert into auth.identities values($1,$2,$3)',[ids.employee,'google',JSON.stringify({email:hire.email,email_verified:true,custom_claims:{hd:'aerinyustudios.com'}})]);await actor('admin');
 await rpc('finish_workspace_account',{personnel_id:employee,claim_token:claim.claim_token,google_user_id:'google-123',auth_user_id:ids.employee});
 const done=(await db.query('select public.claim_workspace_account($1) as r',[employee])).rows[0].r;assert.equal(done.complete,true);
 await actor('employee');assert.equal((await rpc('people_directory')).profile.role,'employee');
});
test('employees cannot read finance, other private profiles, provision accounts or grant privileges',async()=>{
 await actor('employee');const data=await rpc('people_directory');assert.equal(data.own_person_id,employee);assert.ok(!JSON.stringify(data).includes('Private home'));assert.equal(data.onboarding.length,0);
 const own=(await db.query('select public.employee_detail($1) as r',[employee])).rows[0].r;assert.equal(own.personal.residential_address,'Private home');
 const other=(await db.query('select public.employee_detail($1) as r',[second])).rows[0].r;assert.equal(other.personal,null);assert.equal(other.payment,null);assert.equal(other.employment,null);
 for(const table of ['personnel','monthly_records','work_items','adjustments','payments','documents','audit_logs'])assert.equal((await db.query('select * from public.'+table)).rows.length,0,table);
 await assert.rejects(()=>rpc('workspace_data'),/Permission denied/);
 await assert.rejects(()=>db.query('select * from public.employee_private'),/permission denied/i);
 await assert.rejects(()=>db.query('select public.claim_workspace_account($1)',[employee]),/Permission denied/);
 await assert.rejects(()=>rpc('save_profile',{id:ids.employee,full_name:'New Employee',role:'super_admin',active:true}),/Permission denied/);
});
test('personal and payment updates require review and never place their contents in audit logs',async()=>{
 await actor('employee');const req=await rpc('request_employee_change',{personnel_id:employee,kind:'personal',payload:{personal_email:'updated@example.test',phone:'456',date_of_birth:'1999-01-01',residential_address:'New private home',country_of_residence:'Malaysia'}});
 await assert.rejects(()=>rpc('request_employee_change',{personnel_id:second,kind:'personal',payload:{}}),/Permission denied/);
 await assert.rejects(()=>rpc('review_employee_change',{id:req.id,decision:'approved'}),/Permission denied/);
 await actor('finance');await assert.rejects(()=>rpc('review_employee_change',{id:req.id,decision:'approved'}),/Permission denied/);
 await actor('admin');await rpc('review_employee_change',{id:req.id,decision:'approved'});
 await actor('employee');const d=(await db.query('select public.employee_detail($1) as r',[employee])).rows[0].r;assert.equal(d.personal.residential_address,'New private home');
 const pay=await rpc('request_employee_change',{personnel_id:employee,kind:'payment',payload:{payment_method:'bank_transfer',currency:'MYR',bank_name:'Bank',account_holder:'New Employee',account_number:'PRIVATE1234'}});
 await actor('finance');await rpc('review_employee_change',{id:pay.id,decision:'approved'});
 assert.match((await db.query('select public.read_payment_details($1) as r',[employee])).rows[0].r.payment_info,/PRIVATE1234/);
 const audits=await db.query('select * from public.audit_logs');assert.ok(!JSON.stringify(audits).includes('PRIVATE1234'));assert.ok(!JSON.stringify(audits).includes('New private home'));
});
test('manual legacy entries share the counter and inactive staff lose portal access',async()=>{
 await actor('finance');const person=(await rpc('workspace_data')).personnel.find(p=>p.id===employee);await assert.rejects(()=>rpc('save_personnel',{...person,expected_version:person.version,status:'departed'}),/administrator must change/);
 await actor('admin');const detail=(await db.query('select public.employee_detail($1) as r',[employee])).rows[0].r;
 await rpc('update_employee',{...detail.employment,id:employee,expected_version:detail.employment.version,status:'departed',end_date:'2026-09-30'});
 await actor('employee');await assert.rejects(()=>rpc('people_directory'),/Permission denied/);
 await db.exec('reset role');await db.exec('update private.employee_counter set last_number=999');await actor('admin');
 await assert.rejects(()=>rpc('onboard_employee',{...hire,request_id:crypto.randomUUID(),email:'overflow@aerinyustudios.com'}),/999/);
 assert.equal((await rpc('people_directory')).people.length,2);
});
