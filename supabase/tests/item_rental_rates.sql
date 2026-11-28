begin;

do $test$
declare
  lender uuid := gen_random_uuid();
  renter uuid := gen_random_uuid();
  hourly_item bigint;
  daily_item bigint;
  starts timestamptz := date_trunc('hour', now()) + interval '3 days';
  rates record;
  booking public.booking_tb;
  room uuid := gen_random_uuid();
  offer_msg bigint;
begin
  insert into auth.users(id, email)
    select u, u::text || '@example.invalid' from unnest(array[lender, renter]) u;
  insert into identity_private.identity_profiles(user_id, status, legal_name, masked_id, citizen_hmac, is_minor)
    select u, 'approved', 'ผู้ใช้ทดสอบ', '*********1234', md5(u::text) || md5(u::text), false
    from unnest(array[lender, renter]) u;
  update profiles.profile_tb set phone = '0812345678' where user_id = any(array[lender, renter]);

  insert into public.item_tb(user_id, item_name, description, price, daily_price, status, type,
    pickup_location, pickup_address, pickup_latitude, pickup_longitude)
    values (lender, 'ขาตั้งกล้อง', 'ทดสอบ', 50, 300, 'available', 'hourly', 'จุดรับ', 'ที่อยู่', 13.75, 100.5)
    returning id into hourly_item;
  insert into public.item_tb(user_id, item_name, description, price, status, type,
    pickup_location, pickup_address, pickup_latitude, pickup_longitude)
    values (lender, 'เต็นท์', 'ทดสอบ', 400, 'available', 'daily', 'จุดรับ', 'ที่อยู่', 13.75, 100.5)
    returning id into daily_item;

  -- ราคาต่อหน่วยอ่านได้ตรงจากคอลัมน์ ไม่ต้องตีความ price ตาม type
  select hourly_rate, daily_rate into strict rates from public.item_tb where id = hourly_item;
  assert rates.hourly_rate = 50 and rates.daily_rate = 300, format('hourly listing %s', rates);
  select hourly_rate, daily_rate into strict rates from public.item_tb where id = daily_item;
  assert rates.hourly_rate is null and rates.daily_rate = 400, format('daily listing %s', rates);

  update public.item_tb set daily_price = null where id = hourly_item;
  select hourly_rate, daily_rate into strict rates from public.item_tb where id = hourly_item;
  assert rates.hourly_rate = 50 and rates.daily_rate is null, format('hourly only %s', rates);
  update public.item_tb set daily_price = 320 where id = hourly_item;

  begin
    update public.item_tb set hourly_rate = 10 where id = hourly_item;
    raise exception 'generated rate was written directly';
  exception when generated_always then null;
  end;

  -- การจองคิดราคาจากเรตของประเภทที่ผู้เช่าเลือก
  booking := public.create_rental_request(renter, hourly_item, starts, starts + interval '3 hours', 'hourly', 'จุดรับ');
  assert booking.price = 50 and booking.total_price = 150 and booking.type = 'hourly', format('hourly %s', booking);
  delete from public.booking_tb where id = booking.id;

  booking := public.create_rental_request(renter, hourly_item, starts, starts + interval '2 days', 'daily', 'จุดรับ');
  assert booking.price = 320 and booking.total_price = 640 and booking.type = 'daily', format('daily on hourly %s', booking);
  delete from public.booking_tb where id = booking.id;

  booking := public.create_rental_request(renter, daily_item, starts, starts + interval '1 day', 'daily', 'จุดรับ');
  assert booking.price = 400 and booking.total_price = 400 and booking.type = 'daily', format('daily %s', booking);
  delete from public.booking_tb where id = booking.id;

  begin
    perform public.create_rental_request(renter, daily_item, starts, starts + interval '2 hours', 'hourly', 'จุดรับ');
    raise exception 'hourly booking on a daily-only listing was accepted';
  exception when invalid_parameter_value then
    if sqlerrm <> 'rental type does not match item' then raise; end if;
  end;

  -- ข้อเสนอในแชตเปลี่ยนประเภทการเช่าได้ด้วยเรตที่เจ้าของระบุ
  insert into messaging.conversation_tb(id, owner_id, renter_id, item_id) values (room, lender, renter, daily_item);
  insert into messaging.chat_message_tb(conversation_id, sender_id, message)
    values (room, lender, format(E'📋 ข้อเสนอเช่า\n[BOOKING_DATA:{"itemId":%s,"rentalType":"hourly","hourlyRate":70,"status":"pending"}]', daily_item))
    returning id into offer_msg;
  booking := public.create_rental_request(renter, daily_item, starts, starts + interval '2 hours', 'hourly', 'จุดรับ', offer_msg);
  assert booking.price = 70 and booking.total_price = 140 and booking.type = 'hourly', format('offer %s', booking);
end
$test$;

rollback;
