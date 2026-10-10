"use client";
import {useEffect,useState} from "react";
import {FileSearch,ShieldCheck,LockKeyhole} from "lucide-react";
import {useAdminData} from "@/lib/api";
import {date,display,type Row} from "@/lib/catalog";
import {Badge,Empty,type Operation} from "./primitives";
type Detail={request?:Row;evidence?:{id:string;kind:string;deleted:boolean}[];sensitive?:Row};
export default function Identity({rows,preview,guardian,onOperation}:{rows:Row[];preview:boolean;guardian:boolean;onOperation:(op:Operation)=>void}){
 const [selected,setSelected]=useState("");useEffect(()=>setSelected(""),[guardian]);
 const result=useAdminData<Detail>((guardian?"guardian-detail":"identity-detail")+"?id="+selected,preview||!selected);
 const r=result.data?.request;const a=r?.analysis as Row|undefined;
 return <div className="review-grid"><section className="panel queue"><div className="panel-heading"><h2>รายการคำขอ</h2><span className="muted text-sm">ล่าสุดก่อน</span></div>{rows.length?rows.map(row=><button key={String(row.id)} className={"queue-row "+(selected===row.id?"selected":"")} onClick={()=>setSelected(String(row.id))}><div><strong>{display(row.display_name??row.relationship??row.id)}</strong><Badge value={row.status}/></div><small>{date(row.created_at??row.consented_at)} · {display(row.masked_id??row.child_id)}</small></button>):<Empty title="ยังไม่มีคำขอ" detail="เมื่อมีผู้ส่งคำขอ รายการจะแสดงที่นี่"/>}</section>
 <section className="panel review-detail">{!selected?<div className="selection-empty"><FileSearch/><h2>เลือกคำขอเพื่อเริ่มตรวจสอบ</h2><p className="muted">เลือกรายการจากฝั่งซ้ายเพื่อดูข้อมูลและหลักฐาน</p></div>:result.loading?<p className="muted">กำลังโหลดหลักฐาน…</p>:result.error?<p className="error">{result.error}</p>:!r?<Empty title="ไม่พบคำขอ"/>:<>
 <div className="panel-heading"><h2>{guardian?"ตรวจอำนาจผู้ปกครอง":"ตรวจคำขอยืนยันตัวตน"}</h2><Badge value={r.status}/></div>
 <p className="notice"><ShieldCheck size={18}/>AI ช่วยประเมิน เจ้าหน้าที่เป็นผู้ตัดสินใจ</p>
 <dl className="details">{Object.entries(guardian?{ผู้ปกครอง:r.guardian_id,บัญชีผู้เยาว์:r.child_id,ความสัมพันธ์:r.relationship,วันที่ให้ความยินยอม:date(r.consented_at)}:{ชื่อบนบัตร:r.legal_name,เลขบัตร:r.masked_id,ประเภทบัญชี:r.is_minor?"ผู้เยาว์ · ทำธุรกรรมผ่านผู้ปกครอง":"ผู้ใหญ่",วันหมดอายุ:r.lifetime?"บัตรตลอดชีพ":date(r.expires_on)}).map(([k,v])=><div key={k}><dt>{k}</dt><dd>{display(v)}</dd></div>)}</dl>
 <div className="evidence-grid">{result.data?.evidence?.map(e=><div key={e.id}><h3>{e.kind==="card"?"ภาพบัตรประชาชน":e.kind==="selfie"?"ภาพใบหน้า":"หลักฐานอำนาจผู้ปกครอง"}</h3>{e.deleted?<div className="evidence-expired"><LockKeyhole/>หลักฐานถูกลบตามกำหนดแล้ว</div>:<a href={"/api/ops/evidence/"+e.id} target="_blank" rel="noreferrer"><img src={"/api/ops/evidence/"+e.id} alt={e.kind==="card"?"ภาพบัตร":e.kind==="selfie"?"ภาพใบหน้า":"หลักฐานอำนาจผู้ปกครอง"}/></a>}</div>)}</div>
 {!guardian&&<><dl className="details"><div><dt>ความคล้ายใบหน้า (cosine)</dt><dd>{display(a?.face_similarity)}</dd></div><div><dt>คะแนนภาพจริงจากโมเดล</dt><dd>{display(a?.live_score)}</dd></div></dl>{Array.isArray(a?.warnings)&&a.warnings.length>0&&<p className="notice warning">{a.warnings.map(String).join(" · ")}</p>}
 {result.data?.sensitive&&<details><summary>ผลอ่านบัตรและข้อมูลที่ผู้ใช้ส่ง</summary><p className="muted">ตรวจเทียบกับภาพต้นฉบับ ข้อมูลส่วนนี้จะถูกลบตามกำหนด</p><dl className="details">{Object.entries(result.data.sensitive).map(([k,v])=><div key={k}><dt>{{citizen_id:"เลขบัตรที่กรอก",birth_date:"วันเกิดที่กรอก",ocr_text:"ข้อความจาก OCR"}[k]??k}</dt><dd className="pre-wrap">{display(v)}</dd></div>)}</dl></details>}</>}
 {r.reason&&<p className="notice">{display(r.reason)}</p>}
 {r.status==="pending"&&<div className="review-actions">{(!guardian?["corrections","rejected","approved"]:["rejected","approved"]).map(decision=><button key={decision} className={decision==="approved"?"primary":decision==="rejected"?"danger-button":""} disabled={preview} onClick={()=>onOperation({action:guardian?"guardian-review":"identity-review",target:String(r.id),title:decision==="approved"?"อนุมัติคำขอ":decision==="rejected"?"ปฏิเสธคำขอ":"ขอข้อมูลเพิ่ม",review:true,data:{decision},detail:guardian?"ตรวจหลักฐานอำนาจตามกฎหมายและความยินยอมก่อนอนุมัติ":"ตรวจชื่อ ข้อมูลบัตร ใบหน้า และคำเตือนจากโมเดลทั้งหมดก่อนบันทึก"})}>{decision==="approved"?"อนุมัติ":decision==="rejected"?"ปฏิเสธ":"ขอข้อมูลเพิ่ม"}</button>)}</div>}
 </>}</section></div>
}
