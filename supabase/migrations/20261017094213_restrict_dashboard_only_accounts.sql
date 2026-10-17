begin;

-- อ่านสิทธิ์ปัจจุบันจาก Auth โดยไม่เชื่อ metadata ที่ผู้ใช้แก้เองหรือ JWT เก่า
create or replace function app_private.app_access_allowed()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from auth.users u
    where u.id = (select auth.uid())
      and u.raw_app_meta_data->'dashboard_only' is distinct from 'true'::jsonb
  );
$function$;

revoke all on function app_private.app_access_allowed() from public, anon, authenticated;
grant usage on schema app_private to authenticated;
grant execute on function app_private.app_access_allowed() to authenticated, service_role;

-- ใช้ restrictive เพื่อให้เงื่อนไขนี้ยังมีผลร่วมกับ policy เดิมทุกคำสั่ง
do $policies$
declare target text;
begin
  foreach target in array array['item_tb','profile_tb','booking_tb','review_tb','conversation_tb','chat_message_tb'] loop
    execute format('drop policy if exists app_access_only on public.%I', target);
    execute format(
      'create policy app_access_only on public.%I as restrictive for all to authenticated using ((select app_private.app_access_allowed())) with check ((select app_private.app_access_allowed()))',
      target
    );
  end loop;
end;
$policies$;

drop policy if exists app_access_only on storage.objects;
create policy app_access_only on storage.objects
as restrictive for all to authenticated
using ((select app_private.app_access_allowed()))
with check ((select app_private.app_access_allowed()));

-- จำกัดเฉพาะบัญชีที่ร้องขอ โดยคงรหัสผ่านและสิทธิ์เจ้าหน้าที่เดิม
do $account$
declare changed integer;
begin
  update auth.users u
  set raw_app_meta_data = coalesce(u.raw_app_meta_data, '{}'::jsonb) || '{"dashboard_only":true}'::jsonb,
      updated_at = now()
  where lower(u.email) = 'admin_yuemnoi@gmail.com'
    and exists(select 1 from ops_private.staff_accounts s where s.user_id=u.id and s.active);
  get diagnostics changed = row_count;
  if changed <> 1 then
    raise exception 'Expected exactly one active admin_yuemnoi staff account';
  end if;
end;
$account$;

commit;
