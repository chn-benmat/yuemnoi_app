begin;

do $test$
declare
  lender uuid := gen_random_uuid();
  renter uuid := gen_random_uuid();
  listed bigint;
  booked bigint;
  stored text;
  item_status text;
  booking_status text;
begin
  assert app_private.canonical_booking_status('canceled') = 'cancelled';
  assert app_private.canonical_booking_status('ยกเลิก') = 'cancelled';

  insert into auth.users(id, email)
    select u, u::text || '@example.invalid' from unnest(array[lender, renter]) u;
  insert into identity_private.identity_profiles(user_id, status, legal_name, masked_id, citizen_hmac, is_minor)
    select u, 'approved', 'ผู้ใช้ทดสอบ', '*********1234', md5(u::text) || md5(u::text), false
    from unnest(array[lender, renter]) u;
  update profiles.profile_tb set phone = '0812345678' where user_id = any(array[lender, renter]);

  insert into public.item_tb(user_id, item_name, description, price, status, type,
    pickup_location, pickup_address, pickup_latitude, pickup_longitude)
    values (lender, 'ขาตั้งกล้อง', 'ทดสอบ', 300, 'available', 'daily', 'จุดรับ', 'ที่อยู่', 13.75, 100.5)
    returning id into listed;

  -- ทุกสถานะที่ระบบเขียนจริงต้องบันทึกได้
  foreach item_status in array array['pending_review', 'rejected', 'deleted', 'available'] loop
    update public.item_tb set status = item_status where id = listed;
  end loop;

  insert into public.booking_tb(user_id, item_id, status, type, price, total_price,
    start_at, end_at, pickup_location, pickup_address, latitude, longitude)
    values (renter, listed, 'completed', 'daily', 300, 300,
      now() - interval '2 days', now() - interval '1 day', 'จุดรับ', 'ที่อยู่', 13.75, 100.5)
    returning id into booked;
  foreach booking_status in array array['pending', 'confirmed', 'active', 'awaiting_return',
      'return_ready', 'cancelled', 'completed'] loop
    update public.booking_tb set status = booking_status where id = booked;
  end loop;

  update public.booking_tb set status = 'canceled' where id = booked;
  select status into strict stored from public.booking_tb where id = booked;
  assert stored = 'cancelled', format('booking stored %s', stored);

  begin
    update public.item_tb set status = 'rented' where id = listed;
    raise exception 'unknown item status was accepted';
  exception when check_violation then null;
  end;

  begin
    update public.item_tb set status = null where id = listed;
    raise exception 'item without status was accepted';
  exception when not_null_violation then null;
  end;

  begin
    update public.booking_tb set status = 'paid' where id = booked;
    raise exception 'unknown booking status was accepted';
  exception when check_violation then null;
  end;

  begin
    update public.booking_tb set status = null where id = booked;
    raise exception 'booking without status was accepted';
  exception when not_null_violation then null;
  end;

  -- client ที่ล็อกอินแก้สถานะเองได้แค่กลับไปรอพิจารณา และต้องไม่เจอ permission denied จาก trigger
  perform set_config('request.jwt.claims', json_build_object('sub', lender, 'role', 'authenticated')::text, true);
  set local role authenticated;
  update public.item_tb set status = 'rented' where id = listed;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  select status into strict stored from public.item_tb where id = listed;
  assert stored = 'pending_review', format('client item status %s', stored);
end
$test$;

rollback;
