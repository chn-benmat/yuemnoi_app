begin;

do $test$
declare
  owner_id uuid := gen_random_uuid();
  renter_id uuid := gen_random_uuid();
  queued_renter uuid := gen_random_uuid();
  staff_id uuid := gen_random_uuid();
  room_id uuid := gen_random_uuid();
  queue_room uuid := gen_random_uuid();
  item_id bigint;
  rented_id bigint;
  request_id bigint;
  request_message bigint;
  due_at timestamptz := date_trunc('minute', now()) + interval '25 hours';
  delivery record;
begin
  insert into auth.users(id, email)
    select u, u || '@example.invalid' from unnest(array[owner_id, renter_id, queued_renter, staff_id]) u;
  insert into ops_private.staff_accounts(user_id) values (staff_id);
  insert into identity_private.identity_profiles(user_id, status, legal_name, masked_id, citizen_hmac, is_minor)
    select u, 'approved', 'ผู้ใช้ทดสอบ', '*********1234', md5(u::text) || md5(u::text), false
    from unnest(array[owner_id, renter_id, queued_renter]) u;
  update profiles.profile_tb set phone = '0812345678' where user_id = any(array[owner_id, renter_id, queued_renter]);
  perform public.notification_register_device(owner_id, owner_id::text, owner_id::text, 'android');
  perform public.notification_register_device(renter_id, renter_id::text, renter_id::text, 'android');
  perform public.notification_register_device(queued_renter, queued_renter::text, queued_renter::text, 'ios');

  insert into identity_private.identity_requests(user_id, status, consent_version)
    values (renter_id, 'pending', 'identity-v2');
  update identity_private.identity_requests set status = 'approved' where user_id = renter_id;
  assert exists (select 1 from notifications.notification_tb n where n.user_id = renter_id and n.type = 'identity_approved');

  insert into public.item_tb(user_id, item_name, description, status, pickup_location, pickup_address, pickup_latitude, pickup_longitude, hourly_rate, daily_rate)
    values (owner_id, 'กล้อง', 'ทดสอบ', 'pending_review', 'จุดรับ', 'ที่อยู่', 13.75, 100.50, null, 100)
    returning id into item_id;
  perform public.admin_review_item(staff_id, item_id, 'approved', 'อนุมัติทดสอบ');
  update public.item_tb set status = 'pending_review' where id = item_id;
  perform public.admin_review_item(staff_id, item_id, 'approved', 'อนุมัติรายการแก้ไข');
  assert (select count(*) = 2 from notifications.notification_tb n where n.user_id = owner_id and n.type = 'item_approved');

  insert into messaging.conversation_tb(id, owner_id, renter_id, item_id) values
    (room_id, renter_id, owner_id, item_id), (queue_room, owner_id, queued_renter, item_id);
  insert into messaging.chat_message_tb(conversation_id, sender_id, message) values
    (room_id, renter_id, 'สวัสดีจากผู้เช่า'), (room_id, owner_id, 'สวัสดีจากเจ้าของ');
  select r.id, r.rental_request_message_id into request_id, request_message
  from public.create_chat_rental_request(renter_id, room_id, item_id, due_at, due_at + interval '1 day',
    'daily', 'จุดรับ', 'cash', 100) r;
  set constraints all immediate;
  assert (select count(*) = 2 from notifications.notification_tb n where n.conversation_id = room_id and n.type = 'chat_message');
  assert (select count(*) = 1 from notifications.notification_tb n
    where n.conversation_id = room_id and n.type = 'rental_request_received' and n.user_id = owner_id);
  update messaging.chat_message_tb set is_read = true where id = request_message;
  assert not exists (select 1 from public.notification_claim_mobile_outbox(100) c
    where c.payload->>'type' = 'rental_request_received' and c.user_id = owner_id);
  update public.booking_tb set status = 'cancelled' where id = request_id;

  select r.id into rented_id from public.create_rental_request(renter_id, item_id, due_at - interval '1 day', due_at,
    'daily', 'จุดรับ') r;
  for delivery in select * from public.notification_claim_mobile_outbox(100) loop
    perform public.notification_complete_delivery(delivery.id, delivery.lease_token, 'sent');
  end loop;
  update public.booking_tb set status = 'active' where id = rented_id;
  perform public.rental_queue_action(queued_renter, queue_room, 'request', item_id);

  perform public.notification_schedule_mobile_reminders(due_at - interval '61 minutes');
  assert not exists (select 1 from notifications.notification_tb n where n.booking_id = rented_id and n.type like 'rental_due_%');
  perform public.notification_schedule_mobile_reminders(due_at - interval '1 hour');
  perform public.notification_schedule_mobile_reminders(due_at - interval '59 minutes');
  assert (select count(*) = 1 from notifications.notification_tb n where n.booking_id = rented_id and n.type = 'rental_due_1h');
  assert not exists (select 1 from notifications.notification_tb n where n.booking_id = rented_id and n.type = 'rental_due_30m');
  perform public.notification_schedule_mobile_reminders(due_at - interval '30 minutes');
  perform public.notification_schedule_mobile_reminders(due_at - interval '29 minutes');
  assert (select count(*) = 2 from notifications.notification_tb n
    where n.booking_id = rented_id and n.user_id = renter_id and n.type in ('rental_due_1h', 'rental_due_30m'));

  set constraints all deferred;
  update public.booking_tb set status = 'completed' where id = rented_id;
  set constraints all immediate;
  assert (select count(*) = 1 from notifications.notification_tb n
    where n.booking_id = rented_id and n.user_id = renter_id and n.type = 'rental_review_pending');
  assert (select count(*) = 1 from notifications.notification_tb n
    where n.conversation_id = queue_room and n.user_id = queued_renter and n.type = 'rental_queue_ready');
  assert not exists (select 1 from notifications.notification_tb n where n.user_id = queued_renter and n.type = 'chat_message');
  insert into public.review_tb(user_id, booking_id, item_id, rating, description)
    values (renter_id, rented_id, item_id, '5', 'รีวิวทดสอบ');
  create temp table notification_test_claimed on commit drop as select * from public.notification_claim_mobile_outbox(100);
  assert exists (select 1 from notification_test_claimed where user_id = queued_renter and payload->>'type' = 'rental_queue_ready');
  assert not exists (select 1 from notification_test_claimed where user_id = renter_id
    and payload->>'type' in ('rental_due_1h', 'rental_due_30m', 'rental_review_pending'));
end;
$test$;

rollback;
