import Workspace from '@/components/workspace';import {notFound} from 'next/navigation';
const pages:Record<string,string>={personnel:'Personnel','work-records':'Work Records',payments:'Payments',documents:'Documents',projects:'Projects',reports:'Reports',administration:'Administration'};
export default async function Page({params}:{params:Promise<{section:string}>}){const {section}=await params;if(!pages[section])notFound();return <Workspace initialPage={pages[section]}/>;}
