begin;

do $test$
declare
  lender uuid := gen_random_uuid();
  renter uuid := gen_random_uuid();
  equipment_id bigint;
  rental_id bigint;
  result jsonb;
  recorded_time timestamptz;
  deletion_lease uuid := gen_random_uuid();
begin
  assert (select relkind='v' from pg_class where oid='public.rental_handover_payment_tb'::regclass),
    'ตารางรับเงินเดิมต้องอ่านจากแถววงจรการเช่า';

  insert into auth.users(id,email)
  select u,u::text||'@example.invalid' from unnest(array[lender,renter]) u;
  insert into identity_private.identity_profiles(user_id,status,legal_name,masked_id,citizen_hmac,is_minor)
  select u,'approved','ผู้ใช้ทดสอบ','*********1234',md5(u::text)||md5(u::text),false
  from unnest(array[lender,renter]) u;
  update profiles.profile_tb set phone='0812345678' where user_id=any(array[lender,renter]);
  insert into public.item_tb(user_id, item_name, description, status, pickup_location, pickup_address, pickup_latitude, pickup_longitude, hourly_rate, daily_rate)
  values(lender,'กล้องทดสอบ','ทดสอบ','available','จุดรับ','ที่อยู่',13.75,100.5, null, 100)
  returning id into equipment_id;
  insert into public.booking_tb(user_id,item_id,status,type,price,total_price,payment_method,
    start_at,end_at,pickup_location,pickup_address,latitude,longitude)
  values(renter,equipment_id,'confirmed','daily',100,100,'cash',now()-interval '1 minute',
    now()+interval '1 day','จุดรับ','ที่อยู่',13.75,100.5)
  returning id into rental_id;

  assert not has_table_privilege('anon','public.rental_handover_payment_tb','SELECT');
  assert not has_table_privilege('authenticated','public.rental_handover_payment_tb','SELECT');
  assert not has_column_privilege('service_role','app_private.rental_lifecycle_state','photos','SELECT');
  set local role service_role;
  result := public.rental_handover_payment(lender,rental_id,true,null::text,null::text);
  assert result->>'status'='active' and result->>'payment_confirmed'='true';
  select v.confirmed_at into strict recorded_time from public.rental_handover_payment_tb v
  where v.booking_id=rental_id and v.confirmed_by=lender;
  result := public.rental_handover_payment(lender,rental_id,true,null::text,null::text);
  assert exists (select 1 from public.rental_handover_payment_tb v
    where v.booking_id=rental_id and v.confirmed_at=recorded_time);
  result := public.rental_lifecycle_action(renter,rental_id,'session');
  assert result->'return_state'='{}'::jsonb, 'ข้อมูลรับเงินอย่างเดียวไม่ควรแสดงเป็นสถานะคืนของ';
  perform public.rental_lifecycle_action(lender,rental_id,'confirm_receipt');
  result := public.rental_lifecycle_action(renter,rental_id,'session');
  assert (result->'return_state') ? 'completed_at';
  assert not ((result->'return_state') ? 'payment_confirmed_at');
  reset role;

  perform public.account_deletion_schedule(renter);
  update app_private.account_deletions set requested_at=now()-interval '31 days',
    delete_after=now()-interval '1 day',lease_token=deletion_lease,lease_until=now()+interval '5 minutes'
  where user_id=renter;
  perform public.account_deletion_complete(renter,deletion_lease);
  assert exists (select 1 from public.rental_handover_payment_tb v
    where v.booking_id=rental_id and v.confirmed_by=lender and v.confirmed_at=recorded_time);
  assert exists (select 1 from app_private.rental_lifecycle_state s where s.booking_id=rental_id and s.completed_at is null);
end
$test$;

rollback;
