export const WORKSPACE_DOMAIN='aerinyustudios.com';
type Identity={provider:string;identity_data?:Record<string,any>};
// Only provider-owned identity data is trusted. User metadata is editable.
export function isWorkspaceIdentity(user:{email?:string;email_confirmed_at?:string;identities?:Identity[]}){
 const email=user.email?.toLowerCase();
 return !!email&&email.split('@').length===2&&email.split('@')[1]===WORKSPACE_DOMAIN&&!!user.email_confirmed_at&&!!user.identities?.some(i=>i.provider==='google'&&i.identity_data?.custom_claims?.hd===WORKSPACE_DOMAIN&&i.identity_data?.email?.toLowerCase()===email&&i.identity_data?.email_verified===true);
}
// Call only after Supabase has verified the access token with getUser/exchangeCodeForSession.
export function hasOAuthAuthentication(verifiedToken:string){try{const payload=JSON.parse(atob(verifiedToken.split('.')[1].replaceAll('-','+').replaceAll('_','/')));return Array.isArray(payload.amr)&&payload.amr.some((entry:{method:string})=>entry.method==='oauth');}catch{return false;}}
