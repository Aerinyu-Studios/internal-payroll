import {createClient} from '@supabase/supabase-js';
import {NextRequest,NextResponse} from 'next/server';
import {secure} from './server';
export const verifierCookie='as_google_verifier';
export function oauthClient(req:NextRequest){
 let verifier=req.cookies.get(verifierCookie)?.value||'';
 const db=createClient(process.env.SUPABASE_URL!,process.env.SUPABASE_ANON_KEY!,{auth:{flowType:'pkce',storageKey:'as_google',autoRefreshToken:false,persistSession:true,detectSessionInUrl:false,storage:{getItem:key=>key==='as_google-code-verifier'?verifier:null,setItem:(key,value)=>{if(key==='as_google-code-verifier')verifier=value;},removeItem:key=>{if(key==='as_google-code-verifier')verifier='';}}}});
 return {db,writeVerifier:(res:NextResponse)=>res.cookies.set(verifierCookie,verifier,{httpOnly:true,secure:secure(req),sameSite:'lax',path:'/api/auth/google',maxAge:600})};
}
export function clearVerifier(res:NextResponse){res.cookies.set(verifierCookie,'',{httpOnly:true,sameSite:'lax',path:'/api/auth/google',maxAge:0});}
