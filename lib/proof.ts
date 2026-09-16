export const MAX_PROOF_BYTES=4*1024*1024;
export function proofType(bytes:Uint8Array){
 if(bytes[0]===0x25&&bytes[1]===0x50&&bytes[2]===0x44&&bytes[3]===0x46&&bytes[4]===0x2d)return {ext:'pdf',mime:'application/pdf'};
 if(bytes.length>=8&&[137,80,78,71,13,10,26,10].every((v,i)=>bytes[i]===v))return {ext:'png',mime:'image/png'};
 if(bytes[0]===255&&bytes[1]===216&&bytes[2]===255)return {ext:'jpg',mime:'image/jpeg'};
 throw Error('Choose a PDF, PNG or JPEG file.');
}
export async function validateProof(file:File){if(!file.size||file.size>MAX_PROOF_BYTES)throw Error('Choose a PDF, PNG or JPEG no larger than 4 MB.');proofType(new Uint8Array(await file.slice(0,8).arrayBuffer()));}
