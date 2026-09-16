'use client';
import {Select,SelectTrigger,SelectValue,SelectContent,SelectItem} from '@/components/ui/select';
import {Dialog,DialogContent,DialogHeader,DialogTitle,DialogDescription} from '@/components/ui/dialog';
import {Empty,EmptyHeader,EmptyTitle,EmptyDescription,EmptyMedia} from '@/components/ui/empty';
import {Files,LoaderCircle} from 'lucide-react';
import {ReactNode} from 'react';
import {label as displayLabel} from '@/lib/presentation';
export function Field({label,children,wide=false}:{label:string;children:ReactNode;wide?:boolean}){return <label className={'field '+(wide?'wide':'')}><span>{label}</span>{children}</label>}
export function Choice({value,onChange,options,label,disabled=false}:{value:string;onChange:(v:string)=>void;options:(string|{value:string;label:string})[];label?:string;disabled?:boolean}){return <Select value={value} onValueChange={onChange} disabled={disabled}><SelectTrigger aria-label={label} className="choice"><SelectValue/></SelectTrigger><SelectContent>{options.map(o=>{const value=typeof o==='string'?o:o.value;return <SelectItem value={value} key={value}>{typeof o==='string'?displayLabel(o):o.label}</SelectItem>})}</SelectContent></Select>}
export function Modal({title,description,children,onClose,large=false}:{title:string;description:string;children:ReactNode;onClose:()=>void;large?:boolean}){return <Dialog open onOpenChange={v=>{if(!v)onClose()}}><DialogContent className={large?'form-modal large':'form-modal'}><DialogHeader><DialogTitle>{title}</DialogTitle><DialogDescription>{description}</DialogDescription></DialogHeader>{children}</DialogContent></Dialog>}
export function EmptyState({title,description}:{title:string;description:string}){return <Empty className="empty"><EmptyHeader><EmptyMedia><Files size={28}/></EmptyMedia><EmptyTitle>{title}</EmptyTitle><EmptyDescription>{description}</EmptyDescription></EmptyHeader></Empty>}
export function Busy(){return <span className="busy"><LoaderCircle size={16} className="animate-spin"/> Working…</span>}
export function Status({value}:{value:string}){return <span className={'status status-'+value}>{displayLabel(value)}</span>}
export async function api<T=any>(path:string,options?:RequestInit){let res:Response;try{res=await fetch(path,{...options,headers:{...(options?.body instanceof FormData?{}:{'Content-Type':'application/json'}),...options?.headers}});}catch{throw new Error('Connection interrupted. Check your connection and retry.');}const data:any=await res.json().catch(()=>({error:res.status===413?'The file is too large. Maximum size is 4 MB.':'The server could not complete the request. Please retry.'}));if(!res.ok)throw new Error(data.error||'Unable to complete the request.');return data as T;}
export function action(name:string,input:unknown){return api('/api/actions',{method:'POST',body:JSON.stringify({action:name,input})})}
export function monthLabel(month:string){return new Date(month.slice(0,7)+'-01T00:00:00Z').toLocaleDateString('en-GB',{month:'long',year:'numeric',timeZone:'UTC'})}

