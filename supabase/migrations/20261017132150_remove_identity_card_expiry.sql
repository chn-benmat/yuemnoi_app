begin;

-- สิทธิ์ยึดผลอนุมัติและสถานะบัญชี โดยไม่ใช้วันหมดอายุบัตร
CREATE OR REPLACE FUNCTION app_private.eligible_lessor(u uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from identity_private.identity_profiles p where p.user_id=u and p.status='approved')
 and not exists(select 1 from ops_private.account_controls c where c.user_id=u and c.suspended)
$function$;

CREATE OR REPLACE FUNCTION public.admin_action(p_actor uuid, p_action text, p_target text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare r identity_private.identity_requests; why text; desired text; begin
 perform app_private.require_staff(p_actor); why:=nullif(trim(p_data->>'reason'),'');
 -- การอนุมัติไม่บังคับเหตุผล แต่คำสั่งอื่นและเหตุผลที่ส่งมายังต้องผ่านเงื่อนไขเดิม
 if (why is null and not coalesce(p_action='identity-review' and p_data->>'decision'='approved',false))
    or (why is not null and length(why) not between 3 and 500) then raise exception 'reason_required'; end if;
 if p_action='identity-review' then
  select * into r from identity_private.identity_requests where id=p_target::uuid for update;
  if not found or r.status<>'pending' or r.deadline<now() then raise exception 'request_not_pending'; end if;
  if r.user_id=p_actor then raise exception 'self_review_forbidden'; end if;
  desired:=p_data->>'decision';
  if desired is null or desired not in ('approved','rejected','corrections') or coalesce((p_data->>'checked')::boolean,false)=false then raise exception 'manual_review_required'; end if;
  if desired='approved' then
   -- ผลอนุมัติไม่ผูกกับวันหมดอายุบัตร และไม่รับอายุบัตรจาก client รุ่นเดิม
   r.expires_on := null;
   r.lifetime := false;
   if exists(select 1 from identity_private.identity_profiles where citizen_hmac=r.citizen_hmac and status='approved' and user_id<>r.user_id) then raise exception 'identity_duplicate'; end if;
   insert into identity_private.identity_profiles(user_id,status,legal_name,masked_id,citizen_hmac,expires_on,lifetime,is_minor,guardian_id,reviewed_by)
    values(r.user_id,'approved',r.legal_name,r.masked_id,r.citizen_hmac,r.expires_on,r.lifetime,r.is_minor,null,p_actor)
    on conflict(user_id) do update set status='approved',legal_name=excluded.legal_name,masked_id=excluded.masked_id,citizen_hmac=excluded.citizen_hmac,expires_on=excluded.expires_on,lifetime=excluded.lifetime,is_minor=excluded.is_minor,guardian_id=excluded.guardian_id,reviewed_by=p_actor,reviewed_at=now();
  end if;
  update identity_private.identity_requests set status=desired,expires_on=r.expires_on,lifetime=r.lifetime,reason=why,reviewed_by=p_actor,reviewed_at=now(),deadline=now()+interval '7 days' where id=r.id;
  update identity_private.identity_evidence set delete_at=now()+interval '7 days' where request_id=r.id and deleted_at is null;
 elsif p_action='suspend-user' then
  if p_actor=p_target::uuid then raise exception 'self_suspend_forbidden'; end if;
  insert into ops_private.account_controls(user_id,suspended,reason) values(p_target::uuid,(p_data->>'enabled')::boolean,why) on conflict(user_id) do update set suspended=excluded.suspended,reason=excluded.reason,updated_at=now();
 elsif p_action='hide-item' then update public.item_tb set moderation_hidden=(p_data->>'enabled')::boolean where id=p_target::bigint;
 elsif p_action='hide-review' then update public.review_tb set moderation_hidden=(p_data->>'enabled')::boolean where id=p_target::bigint;
 elsif p_action='pilot' then
  if(p_data->>'enabled')::boolean then insert into identity_private.identity_pilot(user_id) values(p_target::uuid) on conflict do nothing; else delete from identity_private.identity_pilot where user_id=p_target::uuid; end if;
 elsif p_action='staff' then
  perform pg_advisory_xact_lock(840103);
  if not(p_data->>'enabled')::boolean and(select count(*) from ops_private.staff_accounts where active)<=1 then raise exception 'last_staff_required'; end if;
  insert into ops_private.staff_accounts(user_id,active) values(p_target::uuid,(p_data->>'enabled')::boolean) on conflict(user_id) do update set active=excluded.active;
 elsif p_action='revoke-identity' then update identity_private.identity_profiles set status='revoked' where user_id=p_target::uuid;
 elsif p_action='complaint' then
  if p_data->>'status' not in ('open','in_progress','resolved') then raise exception 'invalid_status'; end if;
  update ops_private.complaints set status=p_data->>'status',assigned_to=p_actor,resolution=why,updated_at=now() where id=p_target::uuid;
 elsif p_action='settings' then
  if (not (p_data ? 'enforce_identity') and not (p_data ? 'identity_open_to_all'))
    or (p_data ? 'enforce_identity' and jsonb_typeof(p_data->'enforce_identity')<>'boolean')
    or (p_data ? 'identity_open_to_all' and jsonb_typeof(p_data->'identity_open_to_all')<>'boolean')
  then raise exception 'invalid_settings'; end if;
  update ops_private.app_settings set
    enforce_identity=coalesce((p_data->>'enforce_identity')::boolean,enforce_identity),
    identity_open_to_all=coalesce((p_data->>'identity_open_to_all')::boolean,identity_open_to_all),
    updated_at=now() where id;
 else raise exception 'unknown_action'; end if;
 insert into ops_private.staff_audit(actor_id,action,target,reason) values(p_actor,p_action,p_target,why);
 return jsonb_build_object('ok',true);
end $function$;

commit;
