-- ผู้ใช้ที่ล็อกอินต้องเพิ่มอุปกรณ์ได้ผ่าน trigger ทุกตัว (เทสต์อื่นรันเป็น postgres จึงไม่เจอ 42501)
-- และต้องเผยแพร่ประกาศเองไม่ได้
begin;

do $test$
declare
  lender uuid := gen_random_uuid();
  listed bigint;
  stored record;
begin
  insert into auth.users(id, email) values (lender, lender::text || '@example.invalid');
  insert into identity_private.identity_profiles(user_id, status, legal_name, masked_id, citizen_hmac, is_minor)
    values (lender, 'approved', 'ผู้ใช้ทดสอบ', '*********1234', md5(lender::text) || md5(lender::text), false);
  update profiles.profile_tb set phone = '0812345678' where user_id = lender;

  perform set_config('request.jwt.claims', json_build_object('sub', lender, 'role', 'authenticated')::text, true);
  set local role authenticated;

  insert into public.item_tb(user_id, item_name, description, category, status, moderation_hidden, pickup_location, pickup_address, pickup_latitude, pickup_longitude, hourly_rate, daily_rate)
    values (lender, 'ขาตั้งกล้อง', 'ทดสอบ', 'กล้อง', 'pending_review',
      true, 'จุดรับ', 'ที่อยู่', 13.75, 100.5, 50, 300)
    returning id into listed;

  update public.item_tb set item_image_url = array['https://example.invalid/a.jpg'] where id = listed;

  -- client ขอเผยแพร่เอง trigger ต้องคืนสถานะรอพิจารณา
  update public.item_tb set moderation_hidden = false, status = 'available' where id = listed;

  reset role;
  select hourly_rate, daily_rate, status, moderation_hidden into strict stored from public.item_tb where id = listed;
  assert stored.hourly_rate = 50 and stored.daily_rate = 300, format('rates %s', stored);
  assert stored.status = 'pending_review' and stored.moderation_hidden, format('moderation %s', stored);
end
$test$;

rollback;
