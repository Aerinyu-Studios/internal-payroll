import {NextRequest,NextResponse} from 'next/server';
import {checkOrigin,client,configured,failure,withAuth} from '@/lib/server';
export async function GET(req:NextRequest){if(!configured())return NextResponse.json({configured:false},{headers:{'Cache-Control':'no-store'}});return withAuth(req,async(_db,_user,profile)=>NextResponse.json({configured:true,profile}));}
export async function POST(){return NextResponse.json({error:'Use Google Workspace to sign in.'},{status:405});}
export async function DELETE(req:NextRequest){try{checkOrigin(req);const token=req.cookies.get('as_access')?.value;if(token){const db=client(token);await db.auth.setSession({access_token:token,refresh_token:req.cookies.get('as_refresh')?.value||''});await db.auth.signOut();}const res=NextResponse.json({ok:true});res.cookies.delete('as_access');res.cookies.delete('as_refresh');return res;}catch(e){return failure(e)}}
