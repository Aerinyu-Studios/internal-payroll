import {NextRequest,NextResponse} from 'next/server';
import {client,configured,sessionCookies} from '@/lib/server';
import {oauthClient,clearVerifier,verifierCookie} from '@/lib/google-oauth';
import {isWorkspaceIdentity,hasOAuthAuthentication} from '@/lib/workspace-auth';
export async function GET(req:NextRequest){
 const fail=(code:string)=>{const res=NextResponse.redirect(new URL('/login?error='+code,req.url));clearVerifier(res);res.cookies.delete('as_access');res.cookies.delete('as_refresh');res.headers.set('Cache-Control','no-store');return res;};
 const code=req.nextUrl.searchParams.get('code');
 if(!configured()||!code||!req.cookies.get(verifierCookie)?.value)return fail('signin');
 try{
  const {db}=oauthClient(req);const {data,error}=await db.auth.exchangeCodeForSession(code);
  if(error||!data.session||!data.user)return fail('signin');
  if(!isWorkspaceIdentity(data.user)||!hasOAuthAuthentication(data.session.access_token)){await db.auth.signOut({scope:'local'});return fail('domain');}
  const authorized=client(data.session.access_token);
  const {data:profile,error:profileError}=await authorized.from('profiles').select('id,active,role').eq('id',data.user.id).single();
  if(profileError||!profile?.active||!['super_admin','finance','manager','viewer'].includes(profile.role)){await db.auth.signOut({scope:'local'});return fail('access');}
  const res=NextResponse.redirect(new URL('/',req.url));sessionCookies(res,req,data.session);clearVerifier(res);res.headers.set('Cache-Control','no-store');return res;
 }catch{return fail('signin');}
}
