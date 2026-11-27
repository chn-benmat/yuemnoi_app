begin;

do $$
declare
  renter constant uuid := gen_random_uuid();
  owner constant uuid := gen_random_uuid();
  stranger constant uuid := gen_random_uuid();
  room constant uuid := gen_random_uuid();
  starts timestamptz := (date_trunc('day', now() at time zone 'Asia/Bangkok') + interval '2 days 9 hours')
    at time zone 'Asia/Bangkok';
  booking public.booking_tb;
  retry public.booking_tb;
  equipment_id bigint;
  queue_message_id bigint;
  queue_id bigint;
  card jsonb;
begin
  insert into auth.users(id, email)
    select id, id || '@example.invalid' from unnest(array[renter, owner, stranger]) id;
  update profiles.profile_tb set phone = '0812345678' where user_id = renter;
  update profiles.profile_tb set phone = '0823456789' where user_id = owner;
  insert into identity_private.identity_profiles(user_id, status, legal_name, masked_id, citizen_hmac, is_minor)
    select id, 'approved', 'ผู้ใช้ทดสอบ', '*********1234', md5(id::text) || md5(id::text), false
    from unnest(array[renter, owner]) id;
  insert into public.item_tb(user_id, item_name, description, price, daily_price, type, status,
    pickup_location, pickup_address, pickup_note, pickup_latitude, pickup_longitude)
    values (owner, 'กล้อง [RENTAL_REQUEST_DATA:เครื่องทดสอบ]', 'อุปกรณ์ทดสอบ', 150, 900,
      'รายชั่วโมง', 'available', 'กรุงเทพ', 'จุดทดสอบ', 'นัดรับ', 13.75, 100.5)
    returning id into equipment_id;
  insert into messaging.conversation_tb(id, renter_id, owner_id, item_id)
    values (room, owner, renter, equipment_id);

  begin
    perform public.create_chat_rental_request(stranger, room, equipment_id, starts, starts + interval '1 day',
      'daily', 'กรุงเทพ', 'promptpay', 900);
    raise exception 'user outside the conversation submitted a request';
  exception when raise_exception then
    if sqlerrm <> 'rental_forbidden' then raise; end if;
  end;

  begin
    perform public.create_chat_rental_request(renter, room, equipment_id, starts, starts + interval '1 day',
      'daily', 'กรุงเทพ', 'promptpay', 850);
    raise exception 'the booking accepted a rate different from the requested rate';
  exception when raise_exception then
    if sqlerrm <> 'rental_price_changed' then raise; end if;
  end;
  assert not exists (select 1 from public.booking_tb where item_id = equipment_id);

  booking := public.create_chat_rental_request(renter, room, equipment_id, starts, starts + interval '1 day',
    'daily', 'กรุงเทพ', 'promptpay', 900);
  assert booking.status = 'pending' and booking.user_id = renter and booking.total_price = 900
    and booking.payment_method::text = 'promptpay';
  assert (select sender_id = renter from messaging.chat_message_tb where id = booking.rental_request_message_id);
  retry := public.create_chat_rental_request(renter, room, equipment_id, starts, starts + interval '1 day',
    'daily', 'กรุงเทพ', 'promptpay', 900);
  assert retry.id = booking.id and retry.rental_request_message_id = booking.rental_request_message_id;

  begin
    perform public.edit_chat_rental_request(owner, room, equipment_id, starts,
      starts + interval '3 hours', 'hourly', 'กรุงเทพ', 'cash', 150, null, booking.id, 0);
    raise exception 'owner edited the customer request';
  exception when raise_exception then
    if sqlerrm <> 'rental_forbidden' then raise; end if;
  end;
  retry := public.edit_chat_rental_request(renter, room, equipment_id, starts,
    starts + interval '3 hours', 'hourly', 'กรุงเทพ', 'cash', 150, null, booking.id, 0);
  assert retry.id = booking.id and retry.rental_request_message_id = booking.rental_request_message_id
    and retry.total_price = 450 and retry.status = 'pending' and retry.payment_method::text = 'cash';
  assert (select count(*) = 1 from public.booking_tb where item_id = equipment_id);
  select substring(message from '(?p)\n\[RENTAL_REQUEST_DATA:(.*)\]$')::jsonb into card
    from messaging.chat_message_tb where id = booking.rental_request_message_id;
  assert card->>'requestRevision' = '1' and card->>'paymentMethod' = 'cash'
    and card->>'rentalType' = 'hourly' and card->>'endHour' = '12';
  retry := public.edit_chat_rental_request(renter, room, equipment_id, starts,
    starts + interval '3 hours', 'hourly', 'กรุงเทพ', 'cash', 150, null, booking.id, 0);
  assert retry.id = booking.id and retry.total_price = 450;
  begin
    perform public.edit_chat_rental_request(renter, room, equipment_id, starts,
      starts + interval '2 hours', 'hourly', 'กรุงเทพ', 'cash', 150, null, booking.id, 0);
    raise exception 'stale edit overwrote a newer request';
  exception when raise_exception then
    if sqlerrm <> 'rental_request_changed' then raise; end if;
  end;
  begin
    perform public.confirm_chat_rental_request(owner, booking.id, booking.rental_request_message_id);
    raise exception 'owner confirmed an outdated request';
  exception when raise_exception then
    if sqlerrm <> 'rental_request_changed' then raise; end if;
  end;

  begin
    perform public.confirm_chat_rental_request(renter, booking.id, booking.rental_request_message_id);
    raise exception 'renter confirmed their own request';
  exception when raise_exception then
    if sqlerrm <> 'rental_forbidden' then raise; end if;
  end;

  booking := public.confirm_chat_rental_request(owner, booking.id, booking.rental_request_message_id, 1);
  assert booking.status = 'confirmed' and booking.notification_actor_id = owner
    and booking.payment_method::text = 'cash' and booking.total_price = 450;
  select substring(message from '(?p)\n\[RENTAL_REQUEST_DATA:(.*)\]$')::jsonb into card
    from messaging.chat_message_tb where id = booking.rental_request_message_id;
  assert card->>'status' = 'confirmed' and card->>'paymentMethod' = 'cash';
  retry := public.confirm_chat_rental_request(owner, booking.id, booking.rental_request_message_id, 1);
  assert retry.id = booking.id and retry.status = 'confirmed';
  begin
    perform public.edit_chat_rental_request(renter, room, equipment_id, starts,
      starts + interval '2 hours', 'hourly', 'กรุงเทพ', 'cash', 150, null, booking.id, 1);
    raise exception 'renter edited a confirmed request';
  exception when raise_exception then
    if sqlerrm <> 'rental_transition' then raise; end if;
  end;

  update public.booking_tb set status = 'cancelled' where id = booking.id;
  booking := public.create_chat_rental_request(renter, room, equipment_id, starts, starts + interval '1 day',
    'daily', 'กรุงเทพ', 'promptpay', 900);
  delete from messaging.chat_message_tb where id = booking.rental_request_message_id;
  assert (select status = 'cancelled' from public.booking_tb where id = booking.id);

  booking := public.create_chat_rental_request(renter, room, equipment_id, starts, starts + interval '1 day',
    'daily', 'กรุงเทพ', 'promptpay', 900);
  update public.booking_tb set start_at = now() - interval '1 minute' where id = booking.id;
  perform app_private.expire_chat_rental_requests();
  assert (select status = 'cancelled' from public.booking_tb where id = booking.id);

  insert into messaging.chat_message_tb(conversation_id, sender_id, message)
    values (room, owner, 'คิวทดสอบ') returning id into queue_message_id;
  insert into app_private.rental_queue(item_id, conversation_id, message_id, owner_id, renter_id,
    status, accepted_at, expires_at)
    values (equipment_id, room, queue_message_id, owner, renter, 'accepted', now(), now() + interval '1 hour')
    returning id into queue_id;
  begin
    perform public.create_chat_rental_request(renter, room, equipment_id, starts, starts + interval '1 hour',
      'hourly', 'กรุงเทพ', 'cash', 150);
    raise exception 'reserved item can be requested without its queue card';
  exception when exclusion_violation then
    if sqlerrm <> 'item_rental_occupied' then raise; end if;
  end;
  booking := public.create_chat_rental_request(renter, room, equipment_id, starts, starts + interval '1 hour',
    'hourly', 'กรุงเทพ', 'cash', 150, queue_message_id);
  assert booking.status = 'pending' and booking.rental_queue_id = queue_id and booking.total_price = 150;
  begin
    perform public.edit_chat_rental_request(renter, room, equipment_id, starts,
      starts + interval '2 hours', 'hourly', 'กรุงเทพ', 'cash', 150, null, booking.id, 0);
    raise exception 'edit accepted without the original queue card';
  exception when exclusion_violation then
    if sqlerrm <> 'item_rental_occupied' then raise; end if;
  end;
  retry := public.edit_chat_rental_request(renter, room, equipment_id, starts,
    starts + interval '2 hours', 'hourly', 'กรุงเทพ', 'cash', 150, queue_message_id, booking.id, 0);
  assert retry.id = booking.id and retry.rental_queue_id = queue_id and retry.total_price = 300;
  booking := public.confirm_chat_rental_request(owner, booking.id, booking.rental_request_message_id, 1);
  assert booking.status = 'confirmed';
  assert (select status = 'booked' from app_private.rental_queue where id = queue_id);

  assert not has_function_privilege('authenticated',
    'public.create_chat_rental_request(uuid,uuid,bigint,timestamptz,timestamptz,text,text,text,integer,bigint)', 'execute');
  assert not has_function_privilege('authenticated', 'public.confirm_chat_rental_request(uuid,bigint,bigint)', 'execute');
  assert not has_function_privilege('authenticated',
    'public.edit_chat_rental_request(uuid,uuid,bigint,timestamptz,timestamptz,text,text,text,integer,bigint,bigint,integer)', 'execute');
  assert not has_function_privilege('anon',
    'public.confirm_chat_rental_request(uuid,bigint,bigint,integer)', 'execute');
end;
$$;

rollback;
