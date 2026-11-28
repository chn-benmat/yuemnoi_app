begin;

do $test$
declare
  lender uuid := gen_random_uuid();
  renter uuid := gen_random_uuid();
  listed bigint;
  booked bigint;
  stored record;
begin
  assert app_private.canonical_rental_type('รายชั่วโมง') = 'hourly';
  assert app_private.canonical_rental_type(' Hour ') = 'hourly';
  assert app_private.canonical_rental_type('รายวัน') = 'daily';
  assert app_private.canonical_rental_type('day') = 'daily';
  assert app_private.canonical_item_status('พร้อมใช้งาน') = 'available';
  assert app_private.canonical_booking_status('รอส่งคืน') = 'awaiting_return';
  assert not has_function_privilege('authenticated', 'app_private.canonical_rental_type(text)', 'execute');

  insert into auth.users(id, email)
    select u, u::text || '@example.invalid' from unnest(array[lender, renter]) u;
  insert into identity_private.identity_profiles(user_id, status, legal_name, masked_id, citizen_hmac, is_minor)
    select u, 'approved', 'ผู้ใช้ทดสอบ', '*********1234', md5(u::text) || md5(u::text), false
    from unnest(array[lender, renter]) u;
  update profiles.profile_tb set phone = '0812345678' where user_id = any(array[lender, renter]);

  -- แอปและฟังก์ชันรุ่นเดิมยังส่งค่าภาษาไทยได้ ฐานเก็บเป็นรหัสมาตรฐาน
  insert into public.item_tb(user_id, item_name, description, price, daily_price, status, type,
    pickup_location, pickup_address, pickup_latitude, pickup_longitude)
    values (lender, 'ขาตั้งกล้อง', 'ทดสอบ', 50, 300, 'พร้อมใช้งาน', 'รายชั่วโมง', 'จุดรับ', 'ที่อยู่', 13.75, 100.5)
    returning id into listed;
  select type, status into strict stored from public.item_tb where id = listed;
  assert stored.type = 'hourly' and stored.status = 'available', format('item stored %s', stored);

  update public.item_tb set type = 'รายวัน', daily_price = null where id = listed;
  select type into strict stored from public.item_tb where id = listed;
  assert stored.type = 'daily', format('item updated %s', stored);

  insert into public.booking_tb(user_id, item_id, status, type, price, total_price,
    start_at, end_at, pickup_location, pickup_address, latitude, longitude)
    values (renter, listed, 'รอส่งคืน', 'day', 300, 300,
      now() - interval '2 days', now() - interval '1 day', 'จุดรับ', 'ที่อยู่', 13.75, 100.5)
    returning id into booked;
  select type, status into strict stored from public.booking_tb where id = booked;
  assert stored.type = 'daily' and stored.status = 'awaiting_return', format('booking stored %s', stored);

  begin
    update public.item_tb set type = 'weekly' where id = listed;
    raise exception 'unknown item type was accepted';
  exception when check_violation then null;
  end;

  begin
    update public.booking_tb set type = 'weekly' where id = booked;
    raise exception 'unknown booking type was accepted';
  exception when check_violation then null;
  end;
end
$test$;

rollback;
