import {NextRequest,NextResponse} from 'next/server';
import {withAuth,finance,rpc,ApiError,readLimited} from '@/lib/server';
import {MAX_PROOF_BYTES,proofType} from '@/lib/proof';
import {z} from 'zod';
export async function POST(req:NextRequest,{params}:{params:Promise<{id:string}>}){
 return withAuth(req,async(db,_user,profile)=>{
  finance(profile);const id=z.string().uuid().parse((await params).id);
  const {data:payment,error:paymentError}=await db.from('payments').select('id,proof_path').eq('id',id).single();
  if(paymentError||!payment)throw new ApiError(404,'Payment not found.');
  const contentType=req.headers.get('content-type')||'';
  // Raw binary avoids multipart File-class differences between Node and Workers.
  // Retain multipart support for clients opened before the update.
  let bytes:Uint8Array;
  if(contentType.startsWith('multipart/form-data')){
   const raw=await readLimited(req,MAX_PROOF_BYTES+65536);
   let form:FormData;try{form=await new Response(raw,{headers:{'Content-Type':contentType}}).formData();}catch{throw new ApiError(400,'The upload could not be read. Select the file again.');}
   const file=form.get('file');if(!file||typeof file==='string'||!file.size||file.size>MAX_PROOF_BYTES)throw new ApiError(400,'Choose a PDF, PNG or JPEG no larger than 5 MB.');
   bytes=new Uint8Array(await file.arrayBuffer());
  }else bytes=await readLimited(req,MAX_PROOF_BYTES);
  if(!bytes.length)throw new ApiError(400,'The attachment is empty.');
  let type:ReturnType<typeof proofType>;try{type=proofType(bytes);}catch{throw new ApiError(400,'Choose a PDF, PNG or JPEG file.');}
  const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',Uint8Array.from(bytes).buffer))).map(b=>b.toString(16).padStart(2,'0')).join('');
  // Use UUID-shaped deterministic names to preserve existing storage policies.
  const key=`${digest.slice(0,8)}-${digest.slice(8,12)}-${digest.slice(12,16)}-${digest.slice(16,20)}-${digest.slice(20,32)}`;
  const filename=key+'.'+type.ext,path=`proofs/${id}/${filename}`;
  if(payment.proof_path===path)return NextResponse.json({ok:true});
  if(payment.proof_path)throw new ApiError(409,'A proof is already attached to this payment.');
  const {error}=await db.storage.from('payment-proofs').upload(path,bytes,{contentType:type.mime,upsert:false});
  if(error&&String((error as {statusCode?:string}).statusCode)!=='409')throw new ApiError(502,'Attachment storage is unavailable. The payment is saved; retry attaching the file.');
  await rpc(db,'attach_proof',{input:{id,path,filename}});
  return NextResponse.json({ok:true});
 });
}

export async function GET(req:NextRequest,{params}:{params:Promise<{id:string}>}){return withAuth(req,async(db,_user,profile)=>{finance(profile);const id=z.string().uuid().parse((await params).id);const {data:p}=await db.from('payments').select('proof_path').eq('id',id).single();if(!p?.proof_path)throw new ApiError(404,'No proof is attached.');const {data,error}=await db.storage.from('payment-proofs').download(p.proof_path);if(error)throw new ApiError(502,'Proof could not be retrieved.');const ext=p.proof_path.split('.').pop();return new NextResponse(await data.arrayBuffer(),{headers:{'Content-Type':'application/octet-stream','Content-Disposition':`attachment; filename="payment-proof.${ext}"`,'X-Content-Type-Options':'nosniff'}});});}

