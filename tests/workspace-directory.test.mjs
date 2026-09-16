import {test} from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync,createVerify} from 'node:crypto';
import fs from 'node:fs/promises';
import ts from 'typescript';
await fs.mkdir('work/directory-tests',{recursive:true});
let source=await fs.readFile('lib/workspace-directory.ts','utf8');source=source.replace("'./server'","'./error.mjs'");
await fs.writeFile('work/directory-tests/directory.mjs',ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText);
await fs.writeFile('work/directory-tests/error.mjs',`export class ApiError extends Error{constructor(status,message){super(message);this.status=status}}`);
const {ensureWorkspaceUser,verifyExistingWorkspaceUser}=await import('../work/directory-tests/directory.mjs');
const keys=generateKeyPairSync('rsa',{modulusLength:2048});
process.env.GOOGLE_WORKSPACE_SERVICE_ACCOUNT_JSON=JSON.stringify({client_email:'fixture@fixture.iam.gserviceaccount.com',private_key:keys.privateKey.export({type:'pkcs8',format:'pem'})});
process.env.GOOGLE_WORKSPACE_ADMIN_EMAIL='admin@aerinyustudios.com';
const job={id:'00000000-0000-4000-8000-000000000001',employee_id:'2650011',email:'nexample@aerinyustudios.com',given_name:'New',family_name:'Example',department:'Game Development',position:'Developer',manager_email:'manager@aerinyustudios.com'};
const user={id:'google-user',primaryEmail:job.email,externalIds:[{type:'custom',customType:'aerinyu_personnel_id',value:job.id}]};
function mock(responses){const calls=[];const fn=async(url,options={})=>{calls.push({url,options});const r=responses.shift();assert.ok(r,'Unexpected remote request');return Response.json(r.data||{},{status:r.status||200});};return {fn,calls};}
test('Google provisioning uses signed delegated JWT, exact scope and employee metadata',async()=>{
 const {fn,calls}=mock([{data:{access_token:'test-token'}},{status:404},{data:user}]);const result=await ensureWorkspaceUser(job,fn);
 const jwt=new URLSearchParams(calls[0].options.body).get('assertion');const [h,p,s]=jwt.split('.');const payload=JSON.parse(Buffer.from(p,'base64url'));assert.equal(payload.sub,'admin@aerinyustudios.com');assert.equal(payload.scope,'https://www.googleapis.com/auth/admin.directory.user');assert.equal(payload.aud,'https://oauth2.googleapis.com/token');assert.ok(createVerify('RSA-SHA256').update(h+'.'+p).verify(keys.publicKey,s,'base64url'));
 const sent=JSON.parse(calls[2].options.body);assert.equal(sent.primaryEmail,job.email);assert.equal(sent.changePasswordAtNextLogin,true);assert.equal(sent.externalIds[0].value,'2650011');assert.equal(sent.organizations[0].department,'Game Development');assert.equal(sent.relations[0].value,job.manager_email);assert.ok(sent.password.length>=32);assert.equal(result.temporaryPassword,sent.password);assert.ok(!('recoveryEmail' in sent));assert.ok(!('bank_name' in sent));
});
test('retry recovers an existing matching account without replacing its password',async()=>{
 const {fn,calls}=mock([{data:{access_token:'test-token'}},{data:user}]);const r=await ensureWorkspaceUser(job,fn);assert.equal(r.created,false);assert.equal(r.temporaryPassword,null);assert.equal(calls.length,2);
});
test('conflicting existing addresses cannot be adopted by a new onboarding',async()=>{
 for(const externalIds of [[],[{customType:'aerinyu_personnel_id',value:'another-person'}]]){const {fn,calls}=mock([{data:{access_token:'test-token'}},{data:{...user,externalIds}}]);await assert.rejects(()=>ensureWorkspaceUser(job,fn),/already belongs/);assert.equal(calls.length,2);}
 const {fn}=mock([]);await assert.rejects(()=>ensureWorkspaceUser({...job,email:'attacker@example.com'},fn),/Only aerinyustudios/);
});
test('a concurrent create collision reconciles only the same employee marker',async()=>{
 const {fn}=mock([{data:{access_token:'test-token'}},{status:404},{status:409},{data:user}]);const r=await ensureWorkspaceUser(job,fn);assert.equal(r.temporaryPassword,null);assert.equal(r.created,false);
});
test('Google authorization and API errors are actionable without exposing credentials',async()=>{
 const a=mock([{status:403,data:{error:'SECRET'}}]);await assert.rejects(()=>ensureWorkspaceUser(job,a.fn),/administrator authorization failed/);
 const b=mock([{data:{access_token:'test-token'}},{status:404},{status:403}]);await assert.rejects(()=>ensureWorkspaceUser(job,b.fn),/licences/);
});
test('existing-employee linking requires an active primary company account',async()=>{
 const a=mock([{data:{access_token:'test-token'}},{data:{id:'g',primaryEmail:job.email}}]);assert.equal((await verifyExistingWorkspaceUser(job.email,a.fn)).id,'g');
 for(const data of [{...user,suspended:true},{...user,primaryEmail:'alias@aerinyustudios.com'}]){const b=mock([{data:{access_token:'test-token'}},{data}]);await assert.rejects(()=>verifyExistingWorkspaceUser(job.email,b.fn),/primary company email/);}
});
