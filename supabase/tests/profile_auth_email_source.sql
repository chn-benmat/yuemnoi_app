begin;

do $test$
declare
  customer uuid := gen_random_uuid();
  staff uuid := gen_random_uuid();
  original_email text := 'before-'||gen_random_uuid()||'@example.invalid';
  changed_email text := 'after-'||gen_random_uuid()||'@example.invalid';
  staff_email text := 'staff-'||gen_random_uuid()||'@example.invalid';
  answer jsonb;
begin
  insert into auth.users(id,email) values (customer,original_email), (staff,staff_email);
  insert into ops_private.staff_accounts(user_id) values (staff);
  -- บัญชีแดชบอร์ดตรวจจาก Auth ได้แม้ไม่มีโปรไฟล์แอป
  delete from profiles.profile_tb where user_id=staff;
  update auth.users set email=changed_email where id=customer;
  set local role service_role;
  assert public.check_email_exists(upper(' '||staff_email||' ')), 'บัญชี Auth ที่ไม่มีโปรไฟล์ต้องตรวจเจอ';
  assert public.check_email_exists(changed_email) and not public.check_email_exists(original_email),
    'การเปลี่ยนอีเมลใน Auth ต้องมีผลทันที';
  assert (
    select profiles.email(p)=changed_email from profiles.profile_tb p where p.user_id=customer
  ), 'โปรไฟล์ต้องคืนอีเมลจาก Auth';
  answer := public.admin_read(staff,'users',jsonb_build_object('search',changed_email));
  assert exists (
    select 1 from jsonb_array_elements(answer->'rows') r
    where r->>'user_id'=customer::text and r->>'email'=changed_email
  ), 'แอดมินต้องอ่านอีเมลปัจจุบันได้';
  reset role;
  assert not has_function_privilege('anon','public.check_email_exists(text)','execute');
  assert not has_function_privilege('authenticated','app_private.profile_account_email(uuid)','execute');
  assert not has_function_privilege('authenticated','profiles.email(profiles.profile_tb)','execute');
  assert not exists (
    select 1 from pg_attribute where attrelid='profiles.profile_tb'::regclass
      and attname='email' and not attisdropped
  );
end
$test$;

rollback;
