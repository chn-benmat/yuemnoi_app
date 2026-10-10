import type {Row} from "./catalog";
export type Group="day"|"week"|"month";
export function groupSeries(rows:Row[],group:Group):Row[]{
 const result=new Map<string,Row>();
 for(const row of rows){
  if(typeof row.day!=="string")continue;
  const date=new Date(row.day+"T00:00:00Z");if(!Number.isFinite(date.valueOf()))continue;
  let key=row.day;
  if(group==="month")key=key.slice(0,7)+"-01";
  if(group==="week"){date.setUTCDate(date.getUTCDate()-(date.getUTCDay()+6)%7);key=date.toISOString().slice(0,10)}
  const record=result.get(key)??{day:key,bookings:0,booking_value:0,users:0};
  for(const field of ["bookings","booking_value","users"])record[field]=Number(record[field])+Number(row[field]??0);
  result.set(key,record);
 }
 return [...result.values()].sort((a,b)=>String(a.day).localeCompare(String(b.day)));
}
