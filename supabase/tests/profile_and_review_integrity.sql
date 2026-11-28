begin;

do $test$
declare
  lender uuid := gen_random_uuid();
  renter uuid := gen_random_uuid();
  equipment_id bigint;
  rental_id bigint;
  review_id bigint;
begin
  insert into auth.users(id,email)
  select u,u::text||'@example.invalid' from unnest(array[lender,renter]) u;

  begin
    insert into profiles.profile_tb(user_id) values (renter);
    raise exception 'บัญชีเดียวสร้างโปรไฟล์ซ้ำได้';
  exception when unique_violation then null;
  end;
  begin
    insert into profiles.profile_tb(user_id) values (null);
    raise exception 'สร้างโปรไฟล์ที่ไม่มีบัญชีได้';
  exception when not_null_violation then null;
  end;

  insert into identity_private.identity_profiles(user_id,status,legal_name,masked_id,citizen_hmac,is_minor)
  select u,'approved','ผู้ใช้ทดสอบ','*********1234',md5(u::text)||md5(u::text),false
  from unnest(array[lender,renter]) u;
  update profiles.profile_tb set phone='0812345678' where user_id=any(array[lender,renter]);
  insert into public.item_tb(user_id, item_name, description, status, pickup_location, pickup_address, pickup_latitude, pickup_longitude, hourly_rate, daily_rate)
  values (lender,'กล้องทดสอบ','ทดสอบ','available','จุดรับ','ที่อยู่',13.75,100.5, null, 100)
  returning id into equipment_id;
  insert into public.booking_tb(user_id,item_id,status,type,price,total_price,start_at,end_at,
    pickup_location,pickup_address,latitude,longitude)
  values (renter,equipment_id,'completed','daily',100,100,now()-interval '2 days',now()-interval '1 day',
    'จุดรับ','ที่อยู่',13.75,100.5)
  returning id into rental_id;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', renter::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub',renter,'role','authenticated')::text,true);
  insert into public.review_tb(user_id,item_id,booking_id,rating)
  values(renter,equipment_id,rental_id,4) returning id into review_id;
  update public.review_tb set rating=5,description='ทดสอบแก้ข้อความ' where id=review_id;
  assert (select rating=5 from public.review_tb where id=review_id);
  begin
    update public.review_tb set booking_id=null where id=review_id;
    raise exception 'ผู้ใช้แกะลิงก์รีวิวออกจากใบจองได้';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.review_tb set item_id=null where id=review_id;
    raise exception 'ผู้ใช้เปลี่ยนรายการที่ถูกรีวิวได้';
  exception when insufficient_privilege then null;
  end;
end
$test$;

rollback;
