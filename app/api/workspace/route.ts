import {NextRequest,NextResponse} from 'next/server';
import {withAuth,rpc} from '@/lib/server';
export async function GET(req:NextRequest){return withAuth(req,async db=>NextResponse.json(await rpc(db,'workspace_data')));}
