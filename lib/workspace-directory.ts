import {createSign,randomBytes} from 'node:crypto';
import {ApiError} from './server';

export type AccountJob={id:string;employee_id:string;email:string;given_name:string;family_name:string;department:string;position:string;manager_email:string|null;claim_token:string;complete?:boolean};
type DirectoryUser={id:string;primaryEmail:string;externalIds?:{type:string;customType?:string;value:string}[]};
const DOMAIN='aerinyustudios.com';
const DIRECTORY='https://admin.googleapis.com/admin/directory/v1/users';
export function provisioningConfigured(){return Boolean(process.env.GOOGLE_WORKSPACE_SERVICE_ACCOUNT_JSON&&process.env.GOOGLE_WORKSPACE_ADMIN_EMAIL&&process.env.SUPABASE_SERVICE_ROLE_KEY);}
export function companyEmail(value:string){return /^[a-z0-9]+([._-][a-z0-9]+)*@aerinyustudios\.com$/.test(value);}
export async function directoryToken(fetcher:typeof fetch=fetch){
 let key:{client_email:string;private_key:string};
 try{key=JSON.parse(process.env.GOOGLE_WORKSPACE_SERVICE_ACCOUNT_JSON||'');}catch{throw new ApiError(503,'Google Workspace connection is not configured. Ask your administrator to complete the setup.');}
 const admin=process.env.GOOGLE_WORKSPACE_ADMIN_EMAIL||'';
 if(!key.client_email||!key.private_key||!companyEmail(admin.toLowerCase()))throw new ApiError(503,'Google Workspace administrator settings are incomplete.');
 const now=Math.floor(Date.now()/1000);
 const encode=(value:unknown)=>Buffer.from(JSON.stringify(value)).toString('base64url');
 const content=encode({alg:'RS256',typ:'JWT'})+'.'+encode({iss:key.client_email,sub:admin,scope:'https://www.googleapis.com/auth/admin.directory.user',aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+3600});
 let signature:string;
 try{signature=createSign('RSA-SHA256').update(content).sign(key.private_key,'base64url');}catch{throw new ApiError(503,'The Google Workspace service-account key is invalid.');}
 const response=await fetcher('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:content+'.'+signature}),signal:AbortSignal.timeout(15000)});
 const data:any=await response.json();
 if(!response.ok||!data.access_token)throw new ApiError(502,'Google administrator authorization failed. Check domain-wide delegation, the Directory API scope and the delegated administrator.');
 return data.access_token as string;
}
function directoryError(status:number):never{
 if(status===403)throw new ApiError(502,'Google denied account creation. Check administrator privileges, Directory API access and available Workspace licences.');
 if(status===409)throw new ApiError(409,'This Google Workspace address is already in use. Choose another address.');
 if(status===429)throw new ApiError(429,'Google is temporarily limiting requests. Wait a moment and retry this onboarding.');
 throw new ApiError(502,'Google Workspace could not complete the request. Check the account in Google Admin, then retry this onboarding.');
}
export async function ensureWorkspaceUser(job:AccountJob,fetcher:typeof fetch=fetch){
 if(!companyEmail(job.email))throw new ApiError(400,'Only aerinyustudios.com accounts can be created.');
 const token=await directoryToken(fetcher);
 const headers={Authorization:'Bearer '+token,'Content-Type':'application/json'};
 const get=()=>fetcher(DIRECTORY+'/'+encodeURIComponent(job.email),{headers,signal:AbortSignal.timeout(15000)});
 const match=(user:DirectoryUser)=>{
  if(user.primaryEmail.toLowerCase()!==job.email||!user.externalIds?.some(x=>x.customType==='aerinyu_personnel_id'&&x.value===job.id))throw new ApiError(409,'This address already belongs to another Google account. No account was changed. Ask your Google administrator to resolve the address conflict before retrying.');
  return {user,temporaryPassword:null as string|null,created:false};
 };
 const found=await get();
 if(found.ok)return match(await found.json());
 if(found.status!==404)directoryError(found.status);
 const temporaryPassword=randomBytes(24).toString('base64url')+'aA1!';
 const response=await fetcher(DIRECTORY,{method:'POST',headers,signal:AbortSignal.timeout(15000),body:JSON.stringify({primaryEmail:job.email,name:{givenName:job.given_name,familyName:job.family_name},password:temporaryPassword,changePasswordAtNextLogin:true,orgUnitPath:'/',externalIds:[{type:'organization',value:job.employee_id},{type:'custom',customType:'aerinyu_personnel_id',value:job.id}],organizations:[{name:'Aerinyu Studios',primary:true,type:'work',department:job.department,title:job.position}],...(job.manager_email?.endsWith('@'+DOMAIN)?{relations:[{type:'manager',value:job.manager_email}]}:{})})});
 if(response.status===409){const existing=await get();if(existing.ok)return match(await existing.json());directoryError(existing.status);}
 if(!response.ok)directoryError(response.status);
 return {user:await response.json() as DirectoryUser,temporaryPassword,created:true};
}
export async function verifyExistingWorkspaceUser(email:string,fetcher:typeof fetch=fetch){
 if(!companyEmail(email))throw new ApiError(400,'A company email is required.');
 const token=await directoryToken(fetcher);
 const result=await fetcher(DIRECTORY+'/'+encodeURIComponent(email),{headers:{Authorization:'Bearer '+token},signal:AbortSignal.timeout(15000)});
 if(result.status===404)throw new ApiError(404,'This Google Workspace account does not exist. Create it in Google Admin before linking this existing employee.');
 if(!result.ok)directoryError(result.status);
 const user=await result.json() as DirectoryUser&{suspended?:boolean};
 if(user.primaryEmail.toLowerCase()!==email||user.suspended)throw new ApiError(409,'Use the active account’s primary company email to link employee access.');
 return user;
}
