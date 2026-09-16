import {NextRequest,NextResponse} from 'next/server';import {withAuth,rpc,finance} from '@/lib/server';import {z} from 'zod';
export async function POST(req:NextRequest,{params}:{params:Promise<{id:string}>}){return withAuth(req,async(db,_u,p)=>{finance(p);return NextResponse.json(await rpc(db,'read_payment_details',{person_id:z.string().uuid().parse((await params).id)}));});}
