begin;

do $test$
declare
  seller uuid := gen_random_uuid();
  other_user uuid := gen_random_uuid();
  listed bigint;
  settings record;
begin
  assert not has_function_privilege('anon', 'public.get_item_auto_reply(bigint, uuid)', 'execute');
  assert not has_function_privilege('authenticated', 'public.get_item_auto_reply(bigint, uuid)', 'execute');
  assert not has_function_privilege('anon', 'public.save_item_auto_reply(bigint, uuid, boolean, text)', 'execute');
  assert not has_function_privilege('authenticated', 'public.save_item_auto_reply(bigint, uuid, boolean, text)', 'execute');
  assert not has_table_privilege('authenticated', 'public.item_auto_reply_tb', 'select');

  insert into auth.users(id, email)
    select u, u || '@example.invalid' from unnest(array[seller, other_user]) u;
  insert into identity_private.identity_profiles(user_id, status, legal_name, masked_id, citizen_hmac, is_minor)
    values (seller, 'approved', 'ผู้ใช้ทดสอบ', '*********1234', md5(seller::text) || md5(seller::text), false);
  update profiles.profile_tb set phone = '0812345678' where user_id = seller;
  insert into public.item_tb(user_id, item_name, description, status, pickup_location, pickup_address, pickup_latitude, pickup_longitude, hourly_rate, daily_rate)
    values (seller, 'Tripod', 'Test', 'available', 'Test', 'Test', 13.75, 100.50, null, 150)
    returning id into listed;

  set local role service_role;
  select * into strict settings from public.get_item_auto_reply(listed, seller);
  assert not settings.enabled and settings.message = '';

  assert not exists (select from public.get_item_auto_reply(listed, other_user));
  assert not exists (select from public.save_item_auto_reply(listed, other_user, true, 'wrong seller'));
  assert not exists (select from public.item_auto_reply_tb where item_id = listed);

  select * into strict settings from public.save_item_auto_reply(listed, seller, true, 'Available.');
  assert settings.enabled and settings.message = 'Available.';
  assert not exists (select from public.get_item_auto_reply(listed, other_user));
  assert not exists (select from public.save_item_auto_reply(listed, other_user, false, 'wrong seller'));
  assert exists (select from public.item_auto_reply_tb where item_id = listed and enabled and message = 'Available.');

  insert into public.item_auto_reply_tb(item_id, enabled, message)
    values (listed, true, 'Saved by older Go API.')
    on conflict (item_id) do update set enabled = excluded.enabled, message = excluded.message;
  select * into strict settings from public.get_item_auto_reply(listed, seller);
  assert settings.enabled and settings.message = 'Saved by older Go API.';

  select * into strict settings from public.save_item_auto_reply(listed, seller, false, 'Disabled message.');
  assert not settings.enabled and settings.message = 'Disabled message.';
  assert exists (select from public.item_auto_reply_tb where item_id = listed and not enabled and message = 'Disabled message.');

  begin
    perform public.save_item_auto_reply(listed, seller, true, '');
    raise exception 'An enabled reply must have a nonblank message';
  exception when check_violation then
    null;
  end;
  reset role;
end
$test$;

rollback;
