import {api} from './controls';
import {validateProof} from '@/lib/proof';
export async function uploadProof(id:string,file:File){await validateProof(file);return api('/api/proofs/'+id,{method:'POST',headers:{'Content-Type':'application/octet-stream'},body:await file.arrayBuffer()});}
