begin;

do $$
declare
  renter constant uuid := gen_random_uuid();
  owner constant uuid := gen_random_uuid();
  stranger constant uuid := gen_random_uuid();
  room constant uuid := gen_random_uuid();
  other_room constant uuid := gen_random_uuid();
  starts timestamptz := (date_trunc('day', now() at time zone 'Asia/Bangkok') + interval '2 days 9 hours')
    at time zone 'Asia/Bangkok';
  today_start timestamptz := date_trunc('day', now(), 'Asia/Bangkok');
  booking public.booking_tb;
  retry public.booking_tb;
  expired public.booking_tb;
  cancelled public.booking_tb;
  other_cancelled public.booking_tb;
  equipment_id bigint;
  queue_message_id bigint;
  queue_id bigint;
  card jsonb;
  inquiry_message text;
begin
  insert into auth.users(id, email)
    select id, id || '@example.invalid' from unnest(array[renter, owner, stranger]) id;
  update profiles.profile_tb set phone = '0812345678' where user_id = renter;
  update profiles.profile_tb set phone = '0823456789' where user_id = owner;
  update profiles.profile_tb set phone = '0834567890' where user_id = stranger;
  insert into identity_private.identity_profiles(user_id, status, legal_name, masked_id, citizen_hmac, is_minor)
    select id, 'approved', 'ผู้ใช้ทดสอบ', '*********1234', md5(id::text) || md5(id::text), false
    from unnest(array[renter, owner, stranger]) id;
  insert into public.item_tb(user_id, item_name, description, status, pickup_location, pickup_address, pickup_latitude, pickup_longitude, hourly_rate, daily_rate)
    values (owner, 'กล้อง [RENTAL_REQUEST_DATA:เครื่องทดสอบ]', 'อุปกรณ์ทดสอบ', 'available', 'กรุงเทพ', 'จุดทดสอบ', 13.75, 100.5, 150, 900)
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
  assert booking.pickup_location = 'กรุงเทพ' and booking.pickup_address = 'จุดทดสอบ'
    and booking.latitude::numeric = 13.75 and booking.longitude::numeric = 100.5;
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
  insert into messaging.conversation_tb(id, owner_id, renter_id, item_id)
    values (other_room, owner, stranger, equipment_id);
  other_cancelled := public.create_chat_rental_request(stranger, other_room, equipment_id,
    starts, starts + interval '1 day', 'daily', 'กรุงเทพ', 'cash', 900);
  update public.booking_tb set status = 'cancelled', notification_actor_id = stranger
    where id = other_cancelled.id;

  inquiry_message := format(E'ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:\n[ITEM_INQUIRY:{"itemId":%s,"previousBookingId":%s}]',
    equipment_id, other_cancelled.id);
  perform set_config('request.jwt.claim.sub', stranger::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;
  insert into messaging.chat_message_tb(conversation_id, sender_id, message)
    select other_room, stranger, inquiry_message from generate_series(1, 2);
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  assert (select count(*) = 1 from messaging.chat_message_tb m
    where m.conversation_id = other_room and m.sender_id = stranger and m.message = inquiry_message),
    'another customer must be able to send one inquiry after cancellation';
  assert (select count(*) = 2 from public.booking_tb b
    where b.id in (booking.id, other_cancelled.id) and b.status = 'cancelled' and not b.pickup_deadline_expired),
    'an inquiry must preserve both customer cancellations';

  booking := public.create_chat_rental_request(renter, room, equipment_id, starts, starts + interval '1 day',
    'daily', 'กรุงเทพ', 'promptpay', 900);
  delete from messaging.chat_message_tb where id = booking.rental_request_message_id;
  assert (select status = 'cancelled' from public.booking_tb where id = booking.id);
  cancelled := booking;

  booking := public.create_chat_rental_request(renter, room, equipment_id, starts, starts + interval '1 day',
    'daily', 'กรุงเทพ', 'promptpay', 900);
  update public.booking_tb set start_at = today_start - interval '1 day' where id = booking.id;
  perform app_private.expire_chat_rental_requests();
  assert (select status = 'cancelled' from public.booking_tb where id = booking.id);
  expired := booking;

  begin
    perform public.create_chat_rental_request(renter, room, equipment_id, today_start - interval '1 day', today_start,
      'daily', 'กรุงเทพ', 'cash', 900);
    raise exception 'daily request for yesterday was accepted';
  exception when raise_exception then
    if sqlerrm not in ('rental_not_started', 'rental_request_expired') then raise; end if;
  end;
  begin
    perform public.create_chat_rental_request(renter, room, equipment_id, today_start, today_start + interval '1 hour',
      'hourly', 'กรุงเทพ', 'cash', 150);
    raise exception 'hourly request after its start time was accepted';
  exception when raise_exception then
    if sqlerrm not in ('rental_not_started', 'rental_request_expired') then raise; end if;
  end;

  begin
    perform public.create_chat_rental_request(renter, room, equipment_id, starts, starts + interval '1 day',
      'daily', 'กรุงเทพ', 'cash', 850);
    raise exception 'replacement accepted a stale price';
  exception when raise_exception then
    if sqlerrm <> 'rental_price_changed' then raise; end if;
  end;
  assert exists (select 1 from public.booking_tb where id = expired.id), 'failed replacement removed the old request';
  assert exists (select 1 from messaging.chat_message_tb where id = expired.rental_request_message_id);

  booking := public.create_chat_rental_request(renter, room, equipment_id, today_start, today_start + interval '1 day',
    'daily', 'กรุงเทพ', 'promptpay', 900);
  assert booking.status = 'pending' and booking.total_price = 900;
  assert booking.id <> expired.id;
  assert not exists (select 1 from public.booking_tb where id = expired.id), 'expired request survived replacement';
  assert not exists (select 1 from messaging.chat_message_tb where id = expired.rental_request_message_id);
  assert exists (select 1 from public.booking_tb where id = cancelled.id), 'other cancellation was deleted';
  perform app_private.expire_chat_rental_requests();
  assert (select status = 'pending' from public.booking_tb where id = booking.id);
  retry := public.create_chat_rental_request(renter, room, equipment_id, today_start, today_start + interval '1 day',
    'daily', 'กรุงเทพ', 'promptpay', 900);
  assert retry.id = booking.id;
  retry := public.edit_chat_rental_request(renter, room, equipment_id, today_start,
    today_start + interval '2 days', 'daily', 'กรุงเทพ', 'cash', 900, null, booking.id, 0);
  assert retry.id = booking.id and retry.total_price = 1800;
  booking := public.confirm_chat_rental_request(owner, booking.id, booking.rental_request_message_id, 1);
  assert booking.status = 'confirmed';
  update public.booking_tb set status = 'cancelled' where id = booking.id;

  expired := public.create_chat_rental_request(renter, room, equipment_id, starts, starts + interval '1 day',
    'daily', 'กรุงเทพ', 'cash', 900);
  update public.booking_tb set start_at = today_start - interval '1 day' where id = expired.id;
  perform app_private.expire_chat_rental_requests();
  perform set_config('request.jwt.claim.sub', owner::text, true);
  insert into messaging.chat_message_tb(conversation_id, sender_id, message)
    values (room, owner, format(E'ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:\n[ITEM_INQUIRY:{"itemId":%s,"previousBookingId":%s}]', equipment_id, expired.id));
  assert exists (select 1 from public.booking_tb where id = expired.id), 'another user removed the request';

  perform set_config('request.jwt.claim.sub', renter::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;
  begin
    delete from public.booking_tb where id = expired.id;
    if found then raise exception 'renter deleted an expired request directly'; end if;
  exception when insufficient_privilege then
    null;
  end;
  reset role;
  assert exists (select 1 from public.booking_tb where id = expired.id);
  set local role authenticated;
  insert into messaging.chat_message_tb(conversation_id, sender_id, message)
    select room, renter, format(E'ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:\n[ITEM_INQUIRY:{"itemId":%s,"previousBookingId":%s}]', equipment_id, expired.id)
    from generate_series(1, 2);
  insert into messaging.chat_message_tb(conversation_id, sender_id, message)
    values (room, renter, format(E'ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:\n[ITEM_INQUIRY:{"itemId":%s,"previousBookingId":%s}]', equipment_id, booking.id));
  reset role;
  assert not exists (select 1 from public.booking_tb where id = expired.id), 'expired request survived the inquiry';
  assert not exists (select 1 from messaging.chat_message_tb where id = expired.rental_request_message_id);
  assert (select count(*) = 1 from messaging.chat_message_tb where conversation_id = room and sender_id = renter
    and message like 'ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:%'), 'retry must send one inquiry without creating a booking';
  assert not exists (select 1 from public.booking_tb where item_id = equipment_id and status = 'pending');
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  expired := public.create_chat_rental_request(renter, room, equipment_id, starts, starts + interval '1 day',
    'daily', 'กรุงเทพ', 'cash', 900);
  update public.booking_tb set start_at = today_start - interval '1 day' where id = expired.id;
  perform app_private.expire_chat_rental_requests();
  insert into messaging.chat_message_tb(conversation_id, sender_id, message)
    values (room, renter, format(E'ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:\n[ITEM_INQUIRY:{"itemId":%s,"previousBookingId":%s}]', equipment_id, expired.id));
  perform set_config('request.jwt.claim.sub', renter::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;
  insert into messaging.chat_message_tb(conversation_id, sender_id, message)
    values (room, renter, format(E'ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:\n[ITEM_INQUIRY:{"itemId":%s,"previousBookingId":%s}]', equipment_id, expired.id));
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  assert not exists (select 1 from public.booking_tb where id = expired.id), 'reopening an existing inquiry left its expired request';
  assert (select count(*) = 2 from messaging.chat_message_tb where conversation_id = room and sender_id = renter
    and message like 'ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:%'), 'existing inquiry was duplicated';

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
  booking := public.create_chat_rental_request(renter, room, equipment_id, today_start, today_start + interval '1 day',
    'daily', 'กรุงเทพ', 'cash', 900, queue_message_id);
  assert booking.status = 'pending' and booking.rental_queue_id = queue_id and booking.total_price = 900;
  begin
    perform public.edit_chat_rental_request(renter, room, equipment_id, starts,
      starts + interval '2 hours', 'hourly', 'กรุงเทพ', 'cash', 150, null, booking.id, 0);
    raise exception 'edit accepted without the original queue card';
  exception when exclusion_violation then
    if sqlerrm <> 'item_rental_occupied' then raise; end if;
  end;
  retry := public.edit_chat_rental_request(renter, room, equipment_id, today_start,
    today_start + interval '2 days', 'daily', 'กรุงเทพ', 'cash', 900, queue_message_id, booking.id, 0);
  assert retry.id = booking.id and retry.rental_queue_id = queue_id and retry.total_price = 1800;
  booking := public.confirm_chat_rental_request(owner, booking.id, booking.rental_request_message_id, 1);
  assert booking.status = 'confirmed';
  assert (select status = 'booked' from app_private.rental_queue where id = queue_id);

  update public.booking_tb set status = 'cancelled' where id = booking.id;
  update app_private.rental_queue set status = 'accepted', accepted_at = now(), expires_at = now() + interval '1 hour'
    where id = queue_id;
  booking := public.create_chat_rental_request(renter, room, equipment_id, starts, starts + interval '1 hour',
    'hourly', 'กรุงเทพ', 'cash', 150, queue_message_id);
  update public.booking_tb set start_at = today_start - interval '1 day' where id = booking.id;
  update app_private.rental_queue set expires_at = today_start - interval '2 days' where id = queue_id;
  perform app_private.expire_chat_rental_requests();
  assert (select status = 'cancelled' and not pickup_deadline_expired from public.booking_tb where id = booking.id),
    'queue rights expired before the pickup deadline';

  assert not has_function_privilege('authenticated',
    'public.create_chat_rental_request(uuid,uuid,bigint,timestamptz,timestamptz,text,text,text,integer,bigint)', 'execute');
  assert not has_function_privilege('authenticated', 'public.confirm_chat_rental_request(uuid,bigint,bigint)', 'execute');
  assert not has_function_privilege('authenticated',
    'public.edit_chat_rental_request(uuid,uuid,bigint,timestamptz,timestamptz,text,text,text,integer,bigint,bigint,integer)', 'execute');
  assert not has_function_privilege('anon',
    'public.confirm_chat_rental_request(uuid,bigint,bigint,integer)', 'execute');
  assert not has_function_privilege('authenticated',
    'app_private.remove_expired_customer_rental_requests(uuid,uuid,bigint,bigint)', 'execute');
end;
$$;

rollback;
