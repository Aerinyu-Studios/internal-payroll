import {PDFDocument,rgb,PDFFont,PDFPage} from 'pdf-lib';
import fontkit from '@pdf-lib/fontkit';
import {fontBase64} from './font';
import {logoBase64} from './logo';
import {money,positive} from './money';
import {receiptText,amountInWords} from './receipt-text';
import {label,dateLabel,decimalLabel} from './presentation';
import type {Doc} from './types';
const ink=rgb(.12,.12,.12),grey=rgb(.38,.38,.38),rule=rgb(.78,.78,.78);
export async function generatePdf(document:Doc){
 const pdf=await PDFDocument.create();pdf.registerFontkit(fontkit);const font=await pdf.embedFont(Uint8Array.from(atob(fontBase64),c=>c.charCodeAt(0)),{subset:true});
 const logo=await pdf.embedPng(Uint8Array.from(atob(logoBase64),c=>c.charCodeAt(0)));
 const supported=new Set(font.getCharacterSet());
 const safe=(s:unknown)=>receiptText(s).replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g,'').replaceAll('\t',' ');
 const validate=(s:string)=>{for(const c of s){if(c!=='\n'&&!supported.has(c.codePointAt(0)!))throw Error('The document contains a character unsupported by the installed font. Install a matching font before issuing this document.');}};
 let page!:PDFPage;let y=0;
 const text=(s:unknown,x:number,top:number,size=10,color=ink)=>{const value=safe(s);validate(value);page.drawText(value,{x,y:top,size,font,color});};
 const line=(top:number)=>page.drawLine({start:{x:48,y:top},end:{x:547,y:top},thickness:.6,color:rule});
 const addPage=()=>{page=pdf.addPage([595.28,841.89]);page.drawImage(logo,{x:483,y:760,width:64,height:64});text('AERINYU STUDIOS',48,790,14);text(document.kind==='receipt'?'PAYMENT RECEIPT':'COMPENSATION STATEMENT',48,768,10,grey);line(753);y=730;};
 const ensure=(height:number)=>{if(y-height<66)addPage();};
 const wrap=(s:unknown,width:number,size=10)=>{const lines:string[]=[];for(const paragraph of safe(s).split('\n')){let current='';for(const word of paragraph.split(' ')){if(font.widthOfTextAtSize(current+(current?' ':'')+word,size)<=width){current+=(current?' ':'')+word;}else{if(current)lines.push(current);current='';for(const c of word){if(font.widthOfTextAtSize(current+c,size)>width){lines.push(current);current=c;}else current+=c;}}}lines.push(current);}return lines;};
 const paragraph=(s:unknown,width=499,size=10)=>{for(const t of wrap(s,width,size)){ensure(16);text(t,48,y,size);y-=15;}};
 const field=(label:string,value:unknown)=>{ensure(36);text(label.toUpperCase(),48,y,8,grey);y-=15;paragraph(value);y-=7;};
 const section=(title:string)=>{ensure(40);y-=6;text(title.toUpperCase(),48,y,9);y-=10;line(y);y-=16;};
 const infoRow=(fields:[string,unknown][])=>{const width=499/fields.length;const values=fields.map(([,v])=>wrap(v,width-20,9));const height=19+Math.max(...values.map(v=>v.length))*13;ensure(height);fields.forEach(([label],i)=>{text(label.toUpperCase(),48+i*width,y,8,grey);values[i].forEach((line,n)=>text(line,48+i*width,y-16-n*13,9));});y-=height;};
 const totals=(label:string,value:string,emphasis=false)=>{ensure(30);if(emphasis){line(y+7);y-=12;}text(label,48,y,emphasis?12:10);const formatted=money(value,document.snapshot.record.currency);text(formatted,547-font.widthOfTextAtSize(formatted,emphasis?12:10),y,emphasis?12:10);y-=emphasis?34:22;};
 const s=document.snapshot,r=s.record,p=s.personnel,payment=s.payment;
 pdf.setTitle(safe(`${document.document_number} - ${document.kind==='receipt'?'Payment receipt':'Compensation statement'}`));pdf.setAuthor('Aerinyu Studios');pdf.setSubject('Private personnel and compensation record');pdf.setCreationDate(new Date(s.issued_at));pdf.setModificationDate(new Date(s.issued_at));
 addPage();
 if(document.kind==='receipt'){
  const reportingPeriod=new Date(r.period+'T00:00:00Z').toLocaleDateString('en-GB',{month:'long',year:'numeric',timeZone:'UTC'});
  text('PAID TO',48,y,9);text('RECEIPT DETAILS',355,y,9);y-=22;
  const left=[p.legal_name,p.personnel_code,p.position,p.department];const right=[['Receipt no.',document.document_number],['Payment date',dateLabel(payment.payment_date)],['Reporting period',reportingPeriod]];
  let leftY=y,rightY=y;for(const value of left){for(const t of wrap(value,270,10)){text(t,48,leftY,10);leftY-=15;}}
  for(const [label,value] of right){text(label,355,rightY,8,grey);rightY-=13;for(const t of wrap(value,192,9)){text(t,355,rightY,9);rightY-=14;}rightY-=5;}
  y=Math.min(leftY,rightY)-30;
  line(y);y-=18;text('PAYMENT DATE',48,y,8);text('DESCRIPTION / STATEMENT REFERENCE',139,y,8);text(`AMOUNT (${r.currency})`,450,y,8);y-=12;line(y);y-=21;
  text(dateLabel(payment.payment_date),48,y,9);const description=[`Compensation for ${reportingPeriod}`,r.statement_number];let tableHeight=0;for(const d of description){for(const t of wrap(d,295,10)){text(t,139,y-tableHeight,10);tableHeight+=15;}}
  const formatted=money(payment.amount,r.currency).slice(r.currency.length+1);text(formatted,547-font.widthOfTextAtSize(formatted,10),y,10);y-=Math.max(120,tableHeight+25);line(y);y-=23;
  const words=wrap(amountInWords(payment.amount,r.currency),340,8);words.forEach((t,i)=>text(t,48,y-i*12,8));text('TOTAL',423,y,10);text(formatted,547-font.widthOfTextAtSize(formatted,11),y,11);page.drawLine({start:{x:443,y:y-9},end:{x:547,y:y-9},thickness:.6,color:grey});page.drawLine({start:{x:443,y:y-12},end:{x:547,y:y-12},thickness:.6,color:grey});y-=Math.max(40,words.length*12+14);
  line(y);y-=22;infoRow([['Payment method',label(payment.method)],['Transaction reference',payment.reference]]);line(y+7);y-=14;
  infoRow([['Payment status',!positive(payment.remaining_balance)?'Paid in full':'Partial payment'],['Remaining balance at payment',money(payment.remaining_balance,r.currency)]]);
  ensure(75);y-=10;paragraph('This document records payment issued by Aerinyu Studios for the referenced work period.',499,9);y-=8;paragraph('The balance reflects this payment when recorded. Subsequent payments and corrections are maintained in the associated record.',499,8);
 }else{
  infoRow([['Document number',document.document_number],['Reporting period',new Date(r.period+'T00:00:00Z').toLocaleDateString('en-GB',{month:'long',year:'numeric',timeZone:'UTC'})],['Issue date',dateLabel(s.issued_at)]]);
  section('Personnel information');infoRow([['Recipient',p.legal_name],['Employee ID',p.personnel_code]]);infoRow([['Position / department',`${p.position} / ${p.department}`],['Engagement type',label(p.engagement)]]);
  section('Work summary');
  const cols=[48,111,184,384,437,491],widths=[60,68,193,43,47,56];
  const header=()=>{ensure(40);['Date','Project','Description','Quantity','Rate',`Amount (${r.currency})`].forEach((v,i)=>text(v,i>=3?cols[i]+widths[i]-font.widthOfTextAtSize(v,8):cols[i],y,8,grey));y-=12;line(y);y-=17;};header();
  for(const item of s.items){const cells=[dateLabel(item.completed_on),item.project||'',item.title+(item.description?'\n'+item.description:'')+(item.notes?'\nNotes: '+item.notes:''),item.calculation==='fixed'?'':decimalLabel(item.quantity),item.calculation==='fixed'?'':decimalLabel(item.rate),money(item.amount,r.currency).slice(r.currency.length+1)];const lines=cells.map((v,i)=>wrap(v,widths[i],8));const count=Math.max(...lines.map(l=>l.length));for(let row=0;row<count;row++){if(y<83){addPage();header();}lines.forEach((l,i)=>{if(l[row])text(l[row],i>=3?cols[i]+widths[i]-font.widthOfTextAtSize(l[row],8):cols[i],y,8)});y-=12;}y-=9;line(y+3);y-=10;}
  if(s.adjustments.length){section('Adjustments');for(const a of s.adjustments){ensure(38);text(label(a.kind),48,y,8,grey);const amount=money(a.amount,r.currency);text(amount,547-font.widthOfTextAtSize(amount,10),y,10);y-=16;paragraph(a.description,375,10);if(a.notes&&a.notes!==a.description)paragraph(a.notes,375,9);y-=8;}}
  ensure(160);y-=10;totals('Work subtotal',r.work_subtotal);totals('Additional compensation',r.additional);totals('Reimbursements',r.reimbursements);totals('Deductions',r.deductions);totals('TOTAL PAYABLE',r.total,true);
  if(r.notes){section('Notes');paragraph(r.notes);}y-=8;infoRow([['Approved by',r.approved_by_name],['Approved at',dateLabel(r.approved_at)]]);
 }
 const pages=pdf.getPages();pages.forEach((p,i)=>{page=p;line(49);text('AERINYU STUDIOS',48,34,7,grey);const n=`Page ${i+1} of ${pages.length}`;text(n,547-font.widthOfTextAtSize(n,8),34,8,grey);});
 return pdf.save();
}
