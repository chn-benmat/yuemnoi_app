begin;

do $test$
declare
  owner_id uuid := gen_random_uuid();
  customer_id uuid := gen_random_uuid();
  current_renter_id uuid := gen_random_uuid();
  next_customer_id uuid := gen_random_uuid();
  customer_room uuid := gen_random_uuid();
  current_renter_room uuid := gen_random_uuid();
  next_room uuid := gen_random_uuid();
  rented_item bigint;
  free_item bigint;
  booking_id bigint;
  card_id bigint;
  next_card_id bigint;
  ready_message_id bigint;
  card jsonb;
  items jsonb;
begin
  insert into auth.users(id, email)
    select id, id || '@example.invalid'
    from unnest(array[owner_id, customer_id, current_renter_id, next_customer_id]) id;
  update profiles.profile_tb set phone = '0812345678' where user_id = owner_id;
  update profiles.profile_tb set phone = '0823456789' where user_id = current_renter_id;
  insert into identity_private.identity_profiles(user_id, status, legal_name, masked_id, citizen_hmac, is_minor)
    select id, 'approved', 'ผู้ใช้ทดสอบ', '*********1234', md5(id::text) || md5(id::text), false
    from unnest(array[owner_id, customer_id, current_renter_id, next_customer_id]) id;
  insert into public.item_tb(user_id, item_name, description, price, status, type,
    pickup_location, pickup_address, pickup_latitude, pickup_longitude)
    values (owner_id, 'กล้องที่ถูกเช่า', 'ทดสอบ', 100, 'available', 'daily',
      'จุดรับ', 'ที่อยู่ทดสอบ', 13.75, 100.50)
    returning id into rented_item;
  insert into public.item_tb(user_id, item_name, description, price, status, type,
    pickup_location, pickup_address, pickup_latitude, pickup_longitude)
    values (owner_id, 'กล้องที่ยังว่าง', 'ทดสอบ', 100, 'available', 'daily',
      'จุดรับ', 'ที่อยู่ทดสอบ', 13.75, 100.50)
    returning id into free_item;
  -- สลับช่อง owner_id กับ renter_id ในห้อง เพื่อทดสอบการตรวจเจ้าของจากประกาศ
  insert into messaging.conversation_tb(id, owner_id, renter_id, item_id) values
    (customer_room, customer_id, owner_id, rented_item),
    (current_renter_room, owner_id, current_renter_id, rented_item),
    (next_room, owner_id, next_customer_id, rented_item);
  select id into booking_id from public.create_rental_request(
    current_renter_id, rented_item, now() + interval '1 hour', now() + interval '1 day', 'daily', 'จุดรับ');
  if public.rental_queue_action(customer_id, customer_room, 'list')->'items' <> '[]'::jsonb then
    raise exception 'pending booking must not open a queue';
  end if;
  update public.booking_tb set status = 'confirmed' where id = booking_id;
  items := public.rental_queue_action(customer_id, customer_room, 'list')->'items';
  if jsonb_array_length(items) <> 1 or (items->0->>'id')::bigint is distinct from rented_item then
    raise exception 'expected only the actively occupied item, got %', items;
  end if;
  if public.rental_queue_action(owner_id, customer_room, 'list')->'items' <> '[]'::jsonb
    or public.rental_queue_action(current_renter_id, current_renter_room, 'list')->'items' <> '[]'::jsonb then
    raise exception 'the owner and current renter must not see this item';
  end if;
  begin
    perform public.rental_queue_action(owner_id, customer_room, 'request', rented_item);
    raise exception 'owner was allowed to request a queue for their own item';
  exception when raise_exception then
    if sqlerrm <> 'rental_forbidden' then raise; end if;
  end;
  begin
    perform public.rental_queue_action(current_renter_id, current_renter_room, 'request', rented_item);
    raise exception 'current renter was allowed to request a queue';
  exception when raise_exception then
    if sqlerrm <> 'rental_transition' then raise; end if;
  end;
  begin
    perform public.rental_queue_action(customer_id, customer_room, 'request', free_item);
    raise exception 'customer was allowed to queue for an available item';
  exception when raise_exception then
    if sqlerrm <> 'rental_transition' then raise; end if;
  end;
  card_id := (public.rental_queue_action(customer_id, customer_room, 'request', rented_item)->>'message_id')::bigint;
  select message::jsonb->'rentalQueue' into card from messaging.chat_message_tb
    where id = card_id and sender_id = customer_id;
  if (card->>'status') is distinct from 'waiting' or (card->>'position') is distinct from '1'
    or (card->>'requestedByRenter') is distinct from 'true' or card->>'dueAt' is null then
    raise exception 'expected the customer to send the first waiting card with a due date, got %', card;
  end if;
  if (public.rental_queue_action(customer_id, customer_room, 'request', rented_item)->>'message_id')::bigint
    is distinct from card_id or public.rental_queue_action(customer_id, customer_room, 'list')->'items' <> '[]'::jsonb then
    raise exception 'a second request must reuse the card and the item must be hidden from the picker';
  end if;
  next_card_id := (public.rental_queue_action(next_customer_id, next_room, 'request', rented_item)->>'message_id')::bigint;
  select message::jsonb->'rentalQueue' into card from messaging.chat_message_tb where id = next_card_id;
  if (card->>'status') is distinct from 'waiting' or (card->>'position') is distinct from '2' then
    raise exception 'expected the second customer to wait behind the first, got %', card;
  end if;
  update public.booking_tb set status = 'completed' where id = booking_id;
  select message::jsonb->'rentalQueue' into card from messaging.chat_message_tb where id = card_id;
  ready_message_id := (card->>'readyMessageId')::bigint;
  if (card->>'status') is distinct from 'ready' or not exists (
    select 1 from messaging.chat_message_tb where id = ready_message_id
      and conversation_id = customer_room and sender_id = owner_id
      and message = 'อุปกรณ์พร้อมให้เช่าต่อแล้ว กรุณายืนยันสิทธิ์ในการ์ดคิวภายใน 24 ชั่วโมง'
  ) then
    raise exception 'the original card must reference its owner-sent ready notice, got %', card;
  end if;
  if public.rental_queue_action(current_renter_id, current_renter_room, 'list')->'items' <> '[]'::jsonb then
    raise exception 'a queue hold must not be treated as an active rental';
  end if;
  begin
    perform public.rental_queue_action(current_renter_id, current_renter_room, 'request', rented_item);
    raise exception 'customer was allowed to start a queue for an item held by the queue';
  exception when raise_exception then
    if sqlerrm <> 'rental_transition' then raise; end if;
  end;
  perform public.rental_queue_action(customer_id, customer_room, 'accept', p_message_id => card_id);
  select message::jsonb->'rentalQueue' into card from messaging.chat_message_tb where id = card_id;
  if (card->>'status') is distinct from 'accepted' or (card->>'requestedByRenter') is distinct from 'true'
    or (card->>'readyMessageId')::bigint is distinct from ready_message_id then
    raise exception 'the customer should be able to accept the promoted card they sent, got %', card;
  end if;
  perform public.rental_queue_action(customer_id, customer_room, 'leave', p_message_id => card_id);
  select message::jsonb->'rentalQueue' into card from messaging.chat_message_tb where id = next_card_id;
  if (card->>'status') is distinct from 'ready' then
    raise exception 'the second customer should be promoted after the first leaves, got %', card;
  end if;
  if has_function_privilege('authenticated', 'public.rental_queue_action(uuid,uuid,text,bigint,bigint)', 'execute') then
    raise exception 'clients must not be allowed to call the queue RPC directly';
  end if;
end;
$test$;

rollback;
