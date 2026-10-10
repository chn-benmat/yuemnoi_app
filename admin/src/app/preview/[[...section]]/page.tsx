import {notFound} from "next/navigation";
import Dashboard from "@/components/dashboard";
import {sections} from "@/lib/catalog";
export default async function Preview({params}:{params:Promise<{section?:string[]}>}){
 if(process.env.NODE_ENV!=="development"||process.env.ADMIN_PREVIEW!=="true")notFound();
 const id=(await params).section?.[0]??"overview";if(!sections.some(s=>s.id===id))notFound();
 return <Dashboard section={id} preview/>;
}
