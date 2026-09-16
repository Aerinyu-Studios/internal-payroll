// Display normalization only: stored transaction references remain unchanged.
export function receiptText(value:unknown){return String(value??'').replace(/[\u2013\u2014\u2015]/g,'-');}
const units=['ZERO','ONE','TWO','THREE','FOUR','FIVE','SIX','SEVEN','EIGHT','NINE','TEN','ELEVEN','TWELVE','THIRTEEN','FOURTEEN','FIFTEEN','SIXTEEN','SEVENTEEN','EIGHTEEN','NINETEEN'];
const tens=['','','TWENTY','THIRTY','FORTY','FIFTY','SIXTY','SEVENTY','EIGHTY','NINETY'];
const zero=BigInt(0),ten=BigInt(10),twenty=BigInt(20),hundred=BigInt(100),thousand=BigInt(1000);
function belowThousand(n:bigint):string{if(n<twenty)return units[Number(n)];if(n<hundred)return tens[Number(n/ten)]+(n%ten?' '+units[Number(n%ten)]:'');return units[Number(n/hundred)]+' HUNDRED'+(n%hundred?' '+belowThousand(n%hundred):'');}
function integerWords(n:bigint):string{if(n===zero)return 'ZERO';const parts:string[]=[];const groups=['','THOUSAND','MILLION','BILLION','TRILLION'];let index=0;while(n>zero){const group=n%thousand;if(group)parts.unshift(belowThousand(group)+(groups[index]?' '+groups[index]:''));n/=thousand;index++;}return parts.join(' ');}
export function amountInWords(value:string,currency:string){if(!/^\d+(\.\d{1,4})?$/.test(value))throw Error('Invalid receipt amount.');const [whole,fraction='']=value.split('.');const decimal=(fraction+'00').slice(0,2);const cents=BigInt(decimal);const label=currency==='MYR'?'RINGGIT MALAYSIA':currency;return label+': '+integerWords(BigInt(whole))+(['JPY','KRW'].includes(currency)?'':' AND '+integerWords(cents)+(cents===BigInt(1)?' CENT':' CENTS'))+' ONLY';}
