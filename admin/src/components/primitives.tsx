"use client";
import {useEffect,useRef,useState} from "react";
import {FileText,LoaderCircle,X,ShieldCheck} from "lucide-react";
import {api} from "@/lib/api";
import {display,statusNames,type Row} from "@/lib/catalog";
export function Empty({title="ยังไม่มีรายการ",detail="เมื่อมีข้อมูล รายการจะแสดงที่นี่"}:{title?:string;detail?:string}){return <div className="empty"><span><FileText size={30}/></span><strong>{title}</strong><p>{detail}</p></div>}
export function Badge({value}:{value:unknown}){const key=String(value??"");return <span className={"badge "+(["approved","active","completed","resolved","available"].includes(key)?"success":["rejected","revoked","suspended","cancelled"].includes(key)?"danger":"")}>{statusNames[key]??display(value)}</span>}
export type Column={key:string;label:string;render?:(row:Row)=>React.ReactNode};
export function DataTable({rows,columns,actions}:{rows:Row[];columns:Column[];actions?:(row:Row)=>React.ReactNode}){return <div className="table-scroll"><table><thead><tr>{columns.map(c=><th key={c.key}>{c.label}</th>)}{actions&&<th>จัดการ</th>}</tr></thead><tbody>{rows.map((r,i)=><tr key={String(r.id??r.user_id??i)}>{columns.map(c=><td key={c.key}>{c.render?c.render(r):display(r[c.key])}</td>)}{actions&&<td><div className="row-actions">{actions(r)}</div></td>}</tr>)}</tbody></table>{rows.length===0&&<Empty/>}</div>}
export type Operation={action:string;target:string;title:string;data?:Row;review?:boolean;detail?:string;targetInput?:boolean};
export function ActionDialog({operation,onClose,onSuccess}:{operation:Operation|null;onClose:()=>void;onSuccess:()=>void}){
 const ref=useRef<HTMLDialogElement>(null);const [error,setError]=useState("");const [busy,setBusy]=useState(false);
 useEffect(()=>{setError("");if(operation)ref.current?.showModal();else ref.current?.close()},[operation]);
 async function submit(e:React.FormEvent<HTMLFormElement>){e.preventDefault();if(!operation)return;setBusy(true);setError("");const form=new FormData(e.currentTarget);
  try{const target=operation.targetInput?String(form.get("staff_user_id")).trim():operation.target;await api("actions/"+operation.action+"/"+encodeURIComponent(target),{method:"POST",body:JSON.stringify({...operation.data,reason:form.get("reason"),checked:form.get("checked")==="on"})});onSuccess();onClose()}
  catch(e){setError(e instanceof Error?e.message:"ไม่สามารถบันทึกได้")}finally{setBusy(false)}
 }
 return <dialog ref={ref} onCancel={e=>{e.preventDefault();if(!busy)onClose()}} aria-labelledby="action-title">{operation&&<form onSubmit={submit} key={operation.action+operation.target+String(operation.data?.decision)}>
  <div className="dialog-heading"><h2 id="action-title">{operation.title}</h2><button type="button" className="icon-button" aria-label="ปิด" disabled={busy} onClick={onClose}><X/></button></div>
  {operation.detail&&<p className="muted">{operation.detail}</p>}
  {operation.targetInput&&<label>รหัสบัญชีผู้ใช้ (UUID)<input name="staff_user_id" required pattern="[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}" autoComplete="off"/></label>}
  {operation.review&&<label className="check"><input type="checkbox" name="checked" required/><ShieldCheck size={20}/>ตรวจหลักฐานด้วยตนเองและตรวจสิทธิ์ที่เกี่ยวข้องแล้ว</label>}
  <label>เหตุผลการดำเนินการ<textarea name="reason" minLength={3} maxLength={500} required rows={4} placeholder="ระบุเหตุผลโดยไม่ใส่เลขบัตรหรือข้อมูลส่วนตัวเกินจำเป็น"/></label>
  {error&&<p className="error" role="alert">{error}</p>}<div className="dialog-actions"><button type="button" onClick={onClose} disabled={busy}>ยกเลิก</button><button className="primary" disabled={busy}>{busy&&<LoaderCircle className="spin"/>}ยืนยันและบันทึก</button></div>
 </form>}</dialog>
}
