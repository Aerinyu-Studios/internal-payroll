import {NextRequest,NextResponse} from 'next/server';import {withAuth,rpc} from '@/lib/server';import {z} from 'zod';
export async function GET(req:NextRequest,{params}:{params:Promise<{id:string}>}){return withAuth(req,async db=>NextResponse.json(await rpc(db,'record_detail',{record_id:z.string().uuid().parse((await params).id)})));}
