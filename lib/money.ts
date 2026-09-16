import Decimal from 'decimal.js';
Decimal.set({precision:40,rounding:Decimal.ROUND_HALF_UP});
export const currencies=['MYR','USD','AUD','SGD','EUR','GBP','JPY','KRW','IDR','THB','PHP','INR','CAD','NZD','CNY','HKD'] as const;
export const digits=(currency:string)=>['JPY','KRW'].includes(currency)?0:2;
export function money(value:string|number,currency='MYR'){return `${currency} ${new Decimal(value||0).toFixed(digits(currency)).replace(/\B(?=(\d{3})+(?!\d))/g,',')}`;}
export function lineTotal(item:{calculation:string;quantity:string;rate:string;fixed_amount:string},currency:string){return new Decimal(item.calculation==='fixed'?item.fixed_amount||0:new Decimal(item.quantity||0).mul(item.rate||0)).toDecimalPlaces(digits(currency)).toFixed(digits(currency));}
export function total(items:{calculation:string;quantity:string;rate:string;fixed_amount:string}[],adjustments:{kind:string;amount:string}[],currency:string){return items.reduce((s,i)=>s.plus(lineTotal(i,currency)),new Decimal(0)).plus(adjustments.reduce((s,a)=>s.plus(new Decimal(a.amount||0).mul(a.kind==='deduction'?-1:1)),new Decimal(0))).toDecimalPlaces(digits(currency)).toFixed(digits(currency));}
export function sum(values:(string|number)[]){return values.reduce<Decimal>((s,v)=>s.plus(v||0),new Decimal(0)).toFixed();}
export function subtract(a:string,b:string){return new Decimal(a).minus(b).toFixed();}
export function positive(v:string){return new Decimal(v||0).gt(0);}
export function csvCell(value:unknown){let s=String(value??'');if(/^[=+@\-\t\r]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';}
