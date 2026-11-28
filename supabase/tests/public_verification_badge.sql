begin;

do $test$
declare
  approved_user uuid := gen_random_uuid();
  unverified_user uuid := gen_random_uuid();
begin
  insert into auth.users(id,email)
  select u,u::text||'@example.invalid' from unnest(array[approved_user,unverified_user]) u;

  insert into identity_private.identity_profiles(user_id,status,legal_name,masked_id,citizen_hmac,is_minor)
  values (approved_user,'approved','ผู้ใช้ทดสอบ','*********1234',md5(approved_user::text)||md5(approved_user::text),false);

  set local role anon;
  assert exists (
    select 1 from profiles.public_profile_v p where user_id=approved_user and is_verified
      and not (to_jsonb(p) ?| array['email','phone'])
  ), 'บัญชีที่อนุมัติแล้วต้องมีป้ายโดยไม่เปิดข้อมูลติดต่อ';
  assert exists (
    select 1 from profiles.public_profile_v where user_id=unverified_user and not is_verified
  ), 'บัญชีที่ยังไม่ยืนยันตัวตนต้องไม่มีป้าย';
  reset role;

  perform public.account_deletion_schedule(approved_user);
  set local role anon;
  assert not exists (
    select 1 from profiles.public_profile_v where user_id=approved_user
  ), 'โปรไฟล์ที่รอลบบัญชีต้องซ่อนจากสาธารณะ';
end
$test$;

rollback;
