begin;

do $test$
declare
  lender uuid := gen_random_uuid();
  renter uuid := gen_random_uuid();
  room uuid := gen_random_uuid();
  equipment_id bigint;
  rental public.booking_tb;
  retry public.booking_tb;
  start_time timestamptz := date_trunc('minute',now())+interval '2 days';
  penalty jsonb := '{"damage_fee":200,"late_return_fee":50,"damage_terms":"เลนส์แตก"}';
  previous_updates bigint;
begin
  insert into auth.users(id,email)
  select u,u::text||'@example.invalid' from unnest(array[lender,renter]) u;
  insert into identity_private.identity_profiles(user_id,status,legal_name,masked_id,citizen_hmac,is_minor)
  select u,'approved','ผู้ใช้ทดสอบ','*********1234',md5(u::text)||md5(u::text),false
  from unnest(array[lender,renter]) u;
  update profiles.profile_tb set phone='0812345678' where user_id=any(array[lender,renter]);
  insert into public.item_tb(user_id, item_name, description, status, pickup_location, pickup_address, pickup_latitude, pickup_longitude, damage_fee, late_return_fee, damage_terms, hourly_rate, daily_rate)
  values(lender,'กล้องทดสอบ','ทดสอบ','available','จุดรับ','ที่อยู่',13.75,100.5,200,50,'เลนส์แตก', null, 100)
  returning id into equipment_id;
  insert into messaging.conversation_tb(id,owner_id,renter_id,item_id) values(room,lender,renter,equipment_id);

  previous_updates := pg_stat_get_xact_tuples_updated('messaging.chat_message_tb'::regclass);
  rental := public.create_chat_rental_request_with_penalties(renter,room,equipment_id,
    start_time,start_time+interval '1 day','daily','จุดรับ','cash',100,penalty);
  assert rental.return_penalty_terms=penalty;
  assert exists (
    select 1 from messaging.chat_message_tb m where m.id=rental.rental_request_message_id
      and substring(m.message from '(?p)\n\[RENTAL_REQUEST_DATA:(.*)\]$')::jsonb->'penaltyTerms'=penalty
  );
  assert pg_stat_get_xact_tuples_updated('messaging.chat_message_tb'::regclass)=previous_updates,
    'การสร้างคำขอใหม่ต้องบันทึกเงื่อนไขค่าปรับพร้อมการ์ดครั้งเดียว';

  retry := public.create_chat_rental_request_with_penalties(renter,room,equipment_id,
    start_time,start_time+interval '1 day','daily','จุดรับ','cash',100,penalty);
  assert retry.id=rental.id and retry.rental_request_message_id=rental.rental_request_message_id;
  assert pg_stat_get_xact_tuples_updated('messaging.chat_message_tb'::regclass)=previous_updates,
    'การส่งคำขอเดิมซ้ำต้องไม่เขียนการ์ดซ้ำ';
end
$test$;

rollback;
