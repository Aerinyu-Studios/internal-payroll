'use client';
import {useEffect,useState} from 'react';
import {api} from './controls';
const messages:Record<string,string>={domain:'Use your aerinyustudios.com Google Workspace account.',access:'Your account needs workspace access. Ask an administrator to authorize your account and assign a role.',signin:'Sign-in could not be completed. Please try again.'};
export default function Login(){
 const [error,setError]=useState(''),[busy,setBusy]=useState(false),[ready,setReady]=useState<boolean|null>(null);
 useEffect(()=>{setError(messages[new URLSearchParams(location.search).get('error')||'']||'');fetch('/api/session',{cache:'no-store'}).then(async r=>{const d=await r.json() as {profile?:unknown;configured?:boolean};if(r.ok&&d.profile){location.replace('/');return;}setReady(d.configured!==false);}).catch(()=>{setReady(false);setError('Unable to connect. Please reload the page.');});},[]);
 async function signIn(){setBusy(true);setError('');try{const result=await api('/api/auth/google',{method:'POST'});location.assign(result.url);}catch(e){setError((e as Error).message);setBusy(false);}}
 return <main className="login-screen"><section className="login-card"><div className="login-brand"><img src="/aerinyu-logo.png" alt="Aerinyu Studios logo" width={64} height={64}/><div><strong>AERINYU</strong><span>STUDIOS</span></div></div><h1>Studio workspace</h1><p>Sign in with your company Google account to manage personnel, work records and payments.</p><button className="primary" disabled={busy||ready!==true} onClick={signIn}>{busy?'Connecting to Google…':'Sign in with Google'}</button>{ready===false&&!error&&<p className="error">Sign-in is awaiting configuration. Contact your workspace administrator.</p>}{error&&<p className="error" role="alert">{error}</p>}<p className="login-note">For authorized aerinyustudios.com accounts.<br/>Your administrator assigns your access permissions.</p></section></main>;
}
