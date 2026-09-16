import type {Metadata} from 'next';import './globals.css';
export const metadata:Metadata={title:'Aerinyu Studios | Operations',description:'Private personnel, work records, compensation and payments for Aerinyu Studios.',icons:{icon:'/aerinyu-logo.png'}};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="en"><body>{children}</body></html>}
