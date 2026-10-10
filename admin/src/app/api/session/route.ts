import {cookies} from "next/headers";
import {backend,requestOrigin,sameOrigin,sessionCookie} from "@/lib/server";
export async function POST(request:Request){
 if(!sameOrigin(request))return Response.json({error:"ไม่อนุญาตคำขอนี้"},{status:403});
 try{
  const raw=await request.text();if(raw.length>4000)return new Response(null,{status:413});const input=JSON.parse(raw);
  if(typeof input.email!=="string"||typeof input.password!=="string")return Response.json({error:"กรุณากรอกอีเมลและรหัสผ่าน"},{status:400});
  const login=await backend("/api/auth/login",{method:"POST",body:JSON.stringify({email:input.email,password:input.password})});
  if(!login.ok)return Response.json({error:"อีเมลหรือรหัสผ่านไม่ถูกต้อง"},{status:401});
  const auth=await login.json();if(typeof auth.access_token!=="string")throw new Error("invalid_response");
  if(!(await backend("/api/admin/me",{},auth.access_token)).ok)return Response.json({error:"บัญชีนี้ยังไม่มีสิทธิ์เจ้าหน้าที่"},{status:403});
  const claims=JSON.parse(Buffer.from(auth.access_token.split(".")[1],"base64url").toString());
  const lifetime=Math.min(3600,Math.max(0,Number(claims.exp)-Math.floor(Date.now()/1000)));if(!lifetime)throw new Error("expired_token");
  (await cookies()).set(sessionCookie,auth.access_token,{httpOnly:true,secure:new URL(requestOrigin(request)!).protocol==="https:",sameSite:"strict",path:"/",maxAge:lifetime});
  return Response.json({ok:true},{headers:{"Cache-Control":"no-store"}});
 }catch{return Response.json({error:"ระบบเข้าสู่ระบบยังไม่พร้อม กรุณาลองใหม่"},{status:503})}
}
export async function DELETE(request:Request){
 if(!sameOrigin(request))return new Response(null,{status:403});(await cookies()).delete(sessionCookie);return Response.json({ok:true});
}
