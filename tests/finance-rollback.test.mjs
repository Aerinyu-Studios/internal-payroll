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
before(async()=>{await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);create table auth.identities(user_id uuid,provider text,identity_data jsonb);create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated,anon;grant execute on function auth.uid() to authenticated,anon;create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant select,insert on storage.objects to authenticated;`);for(const migration of ['202609160001_operations.sql','202609160002_reports.sql','202609160003_payment_details.sql','202609160004_employee_receipt_ids.sql','202609160005_google_workspace_access.sql'])await db.exec(await readFile(new URL('../supabase/migrations/'+migration,import.meta.url),'utf8'));for(const [role,id] of Object.entries(ids)){await db.query('insert into auth.users values($1,$2,now())',[id,role+'@aerinyustudios.com']);await db.query('insert into auth.identities values($1,$2,$3)',[id,'google',JSON.stringify({email:role+'@aerinyustudios.com',email_verified:true,custom_claims:{hd:'aerinyustudios.com'}})]);await db.query('insert into public.profiles(id,full_name,role) values($1,$2,$3)',[id,role,role==='admin'?'super_admin':role]);}await actor();});
after(()=>db.close());

const rollback=()=>readFile(new URL('../supabase/migrations/202609160008_retire_people_hub.sql',import.meta.url),'utf8');
test('finance rollback works without People migrations and preserves finance operations',async()=>{
 await db.exec('reset role');await db.exec(await rollback());await db.exec(await rollback());await actor('finance');
 department=(await rpc('save_directory',{kind:'department',id:null,name:'Game Development',code:'GD',status:'active'})).id;
 person=(await rpc('save_personnel',{id:null,expected_version:0,personnel_code:'2699010',legal_name:'Rollback Fixture',display_name:'Fixture',engagement:'employee',department_id:department,position:'Developer',email:'fixture@aerinyustudios.com',phone:'',start_date:'2026-01-01',status:'active',currency:'MYR',default_rate:'10',payment_structure:'hourly',notes:'',payment_info:'Preserved fixture'})).id;
 record=(await rpc('save_record',{id:null,request_id:crypto.randomUUID(),expected_version:0,personnel_id:person,period:'2026-08-01',notes:'',items:[item],adjustments:[]})).id;
 const before=await rpc('workspace_data');
 await db.exec('reset role');await db.exec(await rollback());await actor('finance');
 assert.deepEqual(await rpc('workspace_data'),before);
 await actor('admin');await assert.rejects(()=>rpc('save_profile',{id:ids.viewer,full_name:'Viewer',role:'employee',active:true}),/finance workspace role/);
});
test('finance rollback retires People RPCs, preserves records and disables only employee access',async()=>{
 await actor('finance');const before=await rpc('workspace_data');
 await db.exec('reset role');
 for(const file of ['202609160006_employee_role.sql','202609160007_people_hub.sql'])await db.exec(await readFile(new URL('../supabase/migrations/'+file,import.meta.url),'utf8'));
 const employee='00000000-0000-4000-8000-000000000099';
 await db.query('insert into auth.users values($1,$2,now())',[employee,'employee@aerinyustudios.com']);
 await db.query("insert into public.profiles(id,full_name,role) values($1,'Employee','employee')",[employee]);
 await db.exec(await rollback());await db.exec(await rollback());
 const profiles=(await db.query('select id,role,active from public.profiles')).rows;
 assert.equal(profiles.find(p=>p.id===employee).active,false);
 assert.ok(profiles.filter(p=>p.id!==employee).every(p=>p.active));
 await actor('finance');const after=await rpc('workspace_data');
 assert.deepEqual(after.records,before.records);assert.deepEqual(after.payments,before.payments);assert.deepEqual(after.documents,before.documents);
 assert.equal(after.personnel[0].personnel_code,'2699010');
 assert.equal((await db.query('select payment_info from public.personnel_payment_details where personnel_id=$1',[person])).rows[0].payment_info,'Preserved fixture');
 await actor('admin');
 const functions=(await db.query("select p.oid::regprocedure::text as signature,has_function_privilege('authenticated',p.oid,'execute') as allowed from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('people_directory','employee_detail','onboard_employee','update_employee','set_department_head','set_employee_checklist','request_employee_change','review_employee_change','claim_workspace_account','find_employee_auth_user','finish_workspace_account','fail_workspace_account','existing_employee_account','link_employee_signin')")).rows;
 assert.equal(functions.length,14);assert.ok(functions.every(f=>!f.allowed));
 await assert.rejects(()=>rpc('people_directory'),/permission denied/i);
 await assert.rejects(()=>rpc('onboard_employee',{}),/permission denied/i);
 await assert.rejects(()=>rpc('save_profile',{id:employee,full_name:'Employee',role:'employee',active:true}),/finance workspace role/);
 await actor('finance');const p=(await rpc('workspace_data')).personnel[0];
 await rpc('save_personnel',{...p,expected_version:p.version,personnel_code:'2699012'});
 assert.equal((await rpc('workspace_data')).personnel[0].personnel_code,'2699012');
 await assert.rejects(()=>rpc('save_personnel',{...p,id:null,expected_version:0,personnel_code:'',email:'empty@aerinyustudios.com'}),/seven digits|Employee ID/i);
});
