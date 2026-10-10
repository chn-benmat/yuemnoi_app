import {notFound,redirect} from "next/navigation";
import {staffToken} from "@/lib/server";
import {sections} from "@/lib/catalog";
import Dashboard from "@/components/dashboard";
export default async function Page({params}:{params:Promise<{section:string}>}){
 const {section}=await params;if(!sections.some(s=>s.id===section))notFound();if(!await staffToken())redirect("/login");
 return <Dashboard section={section}/>;
}
