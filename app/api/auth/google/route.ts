import {NextRequest,NextResponse} from 'next/server';
import {configured,checkOrigin,failure,ApiError} from '@/lib/server';
import {oauthClient} from '@/lib/google-oauth';
import {WORKSPACE_DOMAIN} from '@/lib/workspace-auth';
export async function POST(req:NextRequest){try{
 checkOrigin(req);if(!configured())throw new ApiError(503,'Sign-in is not configured yet. Contact your workspace administrator.');
 const {db,writeVerifier}=oauthClient(req);
 const {data,error}=await db.auth.signInWithOAuth({provider:'google',options:{redirectTo:new URL('/api/auth/google/callback',req.url).href,skipBrowserRedirect:true,scopes:'openid email profile',queryParams:{hd:WORKSPACE_DOMAIN,prompt:'select_account'}}});
 if(error||!data.url)throw new ApiError(503,'Google sign-in is unavailable. Check the Google provider configuration in Supabase.');
 const res=NextResponse.json({url:data.url},{headers:{'Cache-Control':'no-store'}});writeVerifier(res);return res;
 }catch(e){return failure(e);}}
