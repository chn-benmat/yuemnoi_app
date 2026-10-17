-- ใช้บัญชีสมมติและ rollback เพื่อทดสอบสิทธิ์โดยไม่แก้บัญชีจริง
begin;

do $verify$
declare
  staff_id uuid := gen_random_uuid();
  user_id uuid := gen_random_uuid();
  changed integer;
  result jsonb;
begin
  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data)
  values (staff_id,staff_id::text || '@example.invalid','{"dashboard_only":true}','{}'),
         (user_id,user_id::text || '@example.invalid','{}','{"dashboard_only":true}');
  insert into ops_private.staff_accounts(user_id) values(staff_id);

  -- จำลอง JWT เก่าที่ไม่มีสิทธิ์ dashboard_only เพื่อยืนยันว่าตรวจฐานข้อมูลปัจจุบัน
  perform set_config('request.jwt.claims',jsonb_build_object('sub',staff_id,'role','authenticated','app_metadata',jsonb_build_object())::text,true);
  perform set_config('role','authenticated',true);
  if app_private.app_access_allowed() then raise exception 'dashboard-only account was allowed into app'; end if;
  if exists(select 1 from public.profile_tb) then raise exception 'dashboard-only profile read was allowed'; end if;
  if exists(select 1 from public.item_tb) then raise exception 'dashboard-only item read was allowed'; end if;
  update public.profile_tb set bio='must-not-update' where profile_tb.user_id=staff_id;
  get diagnostics changed = row_count;
  if changed <> 0 then raise exception 'dashboard-only profile update was allowed'; end if;
  begin
    insert into public.conversation_tb(renter_id,owner_id) values(staff_id,user_id);
    raise exception 'dashboard-only conversation insert was allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into storage.objects(bucket_id,name) values('chat_bk',staff_id::text || '/access-test.jpg');
    raise exception 'dashboard-only storage insert was allowed';
  exception when insufficient_privilege then null;
  end;

  -- metadata ที่ผู้ใช้แก้เองไม่มีผลต่อสิทธิ์ของบัญชีทั่วไป
  perform set_config('request.jwt.claims',jsonb_build_object('sub',user_id,'role','authenticated')::text,true);
  if not app_private.app_access_allowed() then raise exception 'regular account was blocked'; end if;
  if (select count(*) from public.profile_tb) <> 1 then raise exception 'regular profile access was changed'; end if;
  insert into public.conversation_tb(renter_id,owner_id) values(user_id,staff_id);

  -- dashboard ใช้ Go และ service role โดยยังตรวจ staff ก่อนส่งข้อมูล
  perform set_config('role','service_role',true);
  result := public.admin_read(staff_id,'me');
  if result->>'role' <> 'staff' then raise exception 'dashboard access was blocked'; end if;
  begin
    perform public.admin_read(user_id,'me');
    raise exception 'regular account was allowed into dashboard';
  exception when raise_exception then
    if sqlerrm <> 'staff_required' then raise; end if;
  end;
  perform set_config('role','postgres',true);

  if (select count(*) from pg_policies where policyname='app_access_only' and permissive='RESTRICTIVE' and cmd='ALL') <> 7 then
    raise exception 'app access policies are incomplete';
  end if;
end;
$verify$;

rollback;
select 'dashboard-only access assertions passed; fixtures rolled back' as result;
