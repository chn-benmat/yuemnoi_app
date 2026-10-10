"use client";
import {useEffect,useState} from "react";
export async function api<T>(path:string,options:RequestInit={}):Promise<T>{
 const res=await fetch("/api/ops/"+path,{...options,cache:"no-store",headers:{"Content-Type":"application/json",...options.headers}});
 if(res.status===401){window.location.assign("/login");throw Error("เซสชันหมดอายุ")}
 const data=await res.json();if(!res.ok)throw Error(data.error??"ไม่สามารถดำเนินการได้");return data as T;
}
export function useAdminData<T>(path:string,preview:boolean){
 const [data,setData]=useState<T>();const [error,setError]=useState("");const [loading,setLoading]=useState(!preview);const [version,setVersion]=useState(0);
 useEffect(()=>{if(preview)return;let active=true;const controller=new AbortController();setLoading(true);setError("");setData(undefined);
  api<T>(path,{signal:controller.signal}).then(v=>{if(active)setData(v)}).catch(e=>{if(active)setError(e instanceof Error?e.message:"โหลดข้อมูลไม่สำเร็จ")}).finally(()=>{if(active)setLoading(false)});
  return ()=>{active=false;controller.abort()};
 },[path,preview,version]);
 return {data,error,loading,reload:()=>setVersion(v=>v+1)};
}
