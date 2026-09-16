import {NextRequest,NextResponse} from 'next/server';
import {z} from 'zod';
import {withAuth,rpc,body,ApiError} from '@/lib/server';
import {provisioningConfigured} from '@/lib/workspace-directory';
import {peopleActions} from '@/lib/people-schema';
export async function GET(req:NextRequest){return withAuth(req,async(db,_user,profile)=>{
 const id=req.nextUrl.searchParams.get('id');
 if(id)return NextResponse.json(await rpc(db,'employee_detail',{person_id:z.string().uuid().parse(id)}));
 return NextResponse.json({...await rpc(db,'people_directory'),provisioning_configured:profile.role==='super_admin'?provisioningConfigured():undefined});
});}
export async function POST(req:NextRequest){return withAuth(req,async db=>{
 const raw=await body(req);const action=peopleActions[raw.action as keyof typeof peopleActions];
 if(!action)throw new ApiError(400,'Unknown people action.');
 return NextResponse.json(await rpc(db,action.rpc,{input:action.schema.parse(raw.input)}));
});}
