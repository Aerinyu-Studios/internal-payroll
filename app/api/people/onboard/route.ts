import {NextRequest,NextResponse} from 'next/server';
import {createClient} from '@supabase/supabase-js';
import {z} from 'zod';
import {withAuth,rpc,body,ApiError} from '@/lib/server';
import {onboardSchema} from '@/lib/people-schema';
import {ensureWorkspaceUser,verifyExistingWorkspaceUser,provisioningConfigured,type AccountJob} from '@/lib/workspace-directory';
export const runtime='nodejs';
export const maxDuration=60;
export async function POST(req:NextRequest){return withAuth(req,async(db,_user,profile)=>{
 if(profile.role!=='super_admin')throw new ApiError(403,'Administrator access is required to onboard employees.');
 const raw=await body(req);
 if(raw.action==='reserve')return NextResponse.json(await rpc(db,'onboard_employee',{input:onboardSchema.parse(raw.input)}));
 if(!['provision','link'].includes(raw.action))throw new ApiError(400,'Unknown onboarding action.');
 const id=z.string().uuid().parse(raw.personnel_id);
 if(!provisioningConfigured())throw new ApiError(503,'Employee saved. Connect Google Workspace in the deployment settings before creating the company account.');
 if(raw.action==='link'){
  const employee=await rpc(db,'existing_employee_account',{person_id:id});
  await verifyExistingWorkspaceUser(employee.email);
  let authId=employee.auth_user_id;
  if(!authId){const admin=createClient(process.env.SUPABASE_URL!,process.env.SUPABASE_SERVICE_ROLE_KEY!,{auth:{persistSession:false,autoRefreshToken:false}});const result=await admin.auth.admin.createUser({email:employee.email,email_confirm:true});if(result.error){authId=(await rpc(db,'existing_employee_account',{person_id:id})).auth_user_id;if(!authId)throw new ApiError(502,'Could not prepare employee sign-in. Check the Supabase server key and retry.');}else authId=result.data.user.id;}
  await rpc(db,'link_employee_signin',{input:{personnel_id:id,auth_user_id:authId}});
  return NextResponse.json({complete:true,email:employee.email,temporaryPassword:null,message:'Existing Google account linked. Existing administrator or finance roles have been preserved.'});
 }
 const job:AccountJob=await rpc(db,'claim_workspace_account',{person_id:id});
 if(job.complete)return NextResponse.json({complete:true,email:job.email,temporaryPassword:null});
 let account:Awaited<ReturnType<typeof ensureWorkspaceUser>>|undefined;
 try{
  account=await ensureWorkspaceUser(job);
  let authId=await rpc(db,'find_employee_auth_user',{person_id:id});
  if(!authId){
   const admin=createClient(process.env.SUPABASE_URL!,process.env.SUPABASE_SERVICE_ROLE_KEY!,{auth:{persistSession:false,autoRefreshToken:false}});
   const result=await admin.auth.admin.createUser({email:job.email,email_confirm:true,user_metadata:{full_name:job.given_name+' '+job.family_name}});
   if(result.error){authId=await rpc(db,'find_employee_auth_user',{person_id:id});if(!authId)throw new ApiError(502,'Google account created, but app access could not be prepared. Check the Supabase server key, then retry.');}
   else authId=result.data.user.id;
  }
  await rpc(db,'finish_workspace_account',{input:{personnel_id:id,claim_token:job.claim_token,google_user_id:account.user.id,auth_user_id:authId}});
  return NextResponse.json({complete:true,email:job.email,temporaryPassword:account.temporaryPassword,created:account.created});
 }catch(error){
  const message=error instanceof ApiError?error.message:'Connection interrupted. Check Google Admin and retry this onboarding. The employee ID will stay the same.';
  try{await rpc(db,'fail_workspace_account',{input:{personnel_id:id,claim_token:job.claim_token,message}});}catch{/* A timed-out lease is recoverable without allocating another employee. */}
  // Deliver a newly created password once even if the subsequent app-access step failed.
  return NextResponse.json({complete:false,email:job.email,message,temporaryPassword:account?.temporaryPassword||null},{status:202});
 }
});}
