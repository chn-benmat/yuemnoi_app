import {readFile,writeFile,unlink} from "node:fs/promises";
import {join} from "node:path";
import {cookies} from "next/headers";
import {backend,requestOrigin,sameOrigin,sessionCookie} from "@/lib/server";
// การตั้งบัญชีแรกเปิดเฉพาะ loopback และไฟล์ลับที่สร้างไว้ในเครื่อง
export async function POST(request:Request){
 const origin=requestOrigin(request);
 if(!origin||!sameOrigin(request)||!["localhost","127.0.0.1","[::1]"].includes(new URL(origin).hostname))return Response.json({error:"เปิดลิงก์ตั้งรหัสผ่านจาก localhost หรือ 127.0.0.1 ในเครื่องที่เตรียมบัญชีไว้"},{status:403});
 const path=join(process.cwd(),".setup-token.json");
 try{
  const raw=await request.text();if(raw.length>1000)return new Response(null,{status:413});
  const {password}=JSON.parse(raw);if(typeof password!=="string"||password.length<12||password.length>128)return Response.json({error:"ใช้รหัสผ่าน 12–128 ตัวอักษร"},{status:400});
  const setup=JSON.parse(await readFile(path,"utf8"));
  const url=process.env.SUPABASE_URL;const key=process.env.SUPABASE_PUBLISHABLE_KEY;if(!url||!key)throw Error("unconfigured");
  const headers={"apikey":key,"Content-Type":"application/json"};
  let token:string=setup.access_token;
  if(!token){
   const verify=await fetch(url+"/auth/v1/verify",{method:"POST",headers,body:JSON.stringify({token_hash:setup.token_hash,type:"invite"}),cache:"no-store",signal:AbortSignal.timeout(20000)});
   if(!verify.ok)return Response.json({error:"ลิงก์ตั้งรหัสผ่านหมดอายุหรือถูกใช้แล้ว"},{status:410});
   const auth=await verify.json();if(auth.user?.id!==setup.user_id||auth.user?.email!==setup.email)throw Error("account_mismatch");token=auth.access_token;
   await writeFile(path,JSON.stringify({...setup,access_token:token}),{mode:0o600});
  }
  if(!(await backend("/api/admin/me",{},token)).ok)return Response.json({error:"ระบบสิทธิ์เจ้าหน้าที่ยังไม่พร้อม กรุณาลองใหม่"},{status:503});
  const updated=await fetch(url+"/auth/v1/user",{method:"PUT",headers:{...headers,Authorization:"Bearer "+token},body:JSON.stringify({password}),cache:"no-store",signal:AbortSignal.timeout(20000)});
  if(!updated.ok)return Response.json({error:"ตั้งรหัสผ่านไม่สำเร็จ กรุณาเลือกใหม่หรือลองอีกครั้ง"},{status:400});
  const claims=JSON.parse(Buffer.from(token.split(".")[1],"base64url").toString());
  (await cookies()).set(sessionCookie,token,{httpOnly:true,secure:new URL(origin).protocol==="https:",sameSite:"strict",path:"/",maxAge:Math.max(0,Math.min(3600,claims.exp-Math.floor(Date.now()/1000)))});
  await unlink(path);
  return Response.json({ok:true},{headers:{"Cache-Control":"no-store"}});
 }catch{return Response.json({error:"ลิงก์ยังไม่พร้อมหรือหมดอายุ กรุณาให้ผู้ดูแลเตรียมลิงก์ใหม่"},{status:503})}
}
