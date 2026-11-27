begin;

do $test$
declare
  lender uuid := gen_random_uuid();
  renter uuid := gen_random_uuid();
  next_renter uuid := gen_random_uuid();
  queue_room uuid := gen_random_uuid();
  damaged_item bigint;
  late_item bigint;
  damaged_booking bigint;
  late_booking bigint;
  queue_message bigint;
  report jsonb;
begin
  insert into auth.users(id, email)
    select id, id || '@example.invalid' from unnest(array[lender, renter, next_renter]) id;
  insert into identity_private.identity_profiles(user_id, status, legal_name, masked_id, citizen_hmac, is_minor)
    select id, 'approved', 'ผู้ใช้ทดสอบ', '*********1234', md5(id::text) || md5(id::text), false
    from unnest(array[lender, renter, next_renter]) id;
  insert into public.item_tb(user_id, item_name, description, price, status, type,
    pickup_location, pickup_address, pickup_note, pickup_latitude, pickup_longitude, damage_fee, damage_terms)
    values (lender, 'กล้อง', 'ทดสอบ', 100, 'available', 'daily',
      'จุดรับ', 'ที่อยู่ทดสอบ', 'นัดรับ', 13.75, 100.50, 200, 'เลนส์แตก')
    returning id into damaged_item;
  insert into public.item_tb(user_id, item_name, description, price, status, type,
    pickup_location, pickup_address, pickup_note, pickup_latitude, pickup_longitude, late_return_fee)
    values (lender, 'ขาตั้งกล้อง', 'ทดสอบ', 100, 'available', 'daily',
      'จุดรับ', 'ที่อยู่ทดสอบ', 'นัดรับ', 13.75, 100.50, 50)
    returning id into late_item;
  insert into public.rental_promptpay_account_tb(user_id, phone) values (lender, '0812345678');

  perform set_config('yuemnoi.expected_return_penalty_terms',
    '{"damage_fee":200,"late_return_fee":0,"damage_terms":"เลนส์แตก"}', true);
  insert into public.booking_tb(user_id, item_id, status, type, price, total_price,
    start_date, end_date, start_at, end_at)
    values (renter, damaged_item, 'active', 'daily', 100, 100,
      current_date - 2, current_date - 1, now() - interval '2 days', now() - interval '1 day')
    returning id into damaged_booking;
  perform set_config('yuemnoi.expected_return_penalty_terms',
    '{"damage_fee":0,"late_return_fee":50,"damage_terms":""}', true);
  insert into public.booking_tb(user_id, item_id, status, type, price, total_price,
    start_date, end_date, start_at, end_at)
    values (renter, late_item, 'active', 'daily', 100, 100,
      current_date - 2, current_date - 1, now() - interval '2 days', now() - interval '1 day')
    returning id into late_booking;
  perform set_config('yuemnoi.expected_return_penalty_terms', '', true);

  insert into messaging.conversation_tb(id, owner_id, renter_id, item_id)
    values (queue_room, lender, next_renter, damaged_item);
  queue_message := (public.rental_queue_action(next_renter, queue_room, 'request', damaged_item)->>'message_id')::bigint;
  assert (select status = 'waiting' from app_private.rental_queue where message_id = queue_message),
    'the next renter starts in the waiting queue';
  begin
    perform public.rental_return_penalty(renter, damaged_booking, 'save', true, false, 'เลนส์แตก');
    raise exception 'a renter must not be allowed to report damage';
  exception when insufficient_privilege then
    if sqlerrm <> 'rental_forbidden' then raise; end if;
  end;
  assert (select owner_hidden is false from public.item_tb where id = damaged_item),
    'a rejected report must leave the listing visible';

  report := public.rental_return_penalty(lender, damaged_booking, 'save', true, false, 'เลนส์แตก');
  assert (report->>'amount_satang')::bigint = 20000, 'the saved amount must come from the booking terms';
  assert (select owner_hidden is true from public.item_tb where id = damaged_item),
    'saving damage must hide the listing immediately';
  assert (select message::jsonb#>>'{rentalQueue,status}' = 'paused'
    from messaging.chat_message_tb where id = queue_message),
    'saving damage must pause the queue card immediately';
  assert (select status = 'active' from public.booking_tb where id = damaged_booking),
    'saving damage must leave the return open for confirmation';
  assert public.rental_return_penalty(lender, damaged_booking, 'qr')->'amount_satang' = report->'amount_satang',
    'the saved fee must be available for PromptPay immediately';

  perform public.rental_lifecycle_action(lender, damaged_booking, 'confirm_receipt');
  assert (select status = 'completed' from public.booking_tb where id = damaged_booking),
    'the lender can still confirm the return';
  assert (select status = 'waiting' from app_private.rental_queue where message_id = queue_message),
    'confirming the return must leave the queue waiting while the listing is hidden';

  update public.item_tb set owner_hidden = false where id = damaged_item;
  assert (select status = 'ready' from app_private.rental_queue where message_id = queue_message),
    'showing the listing again must resume the queue';
  assert public.rental_return_penalty(lender, damaged_booking, 'save', true, false, 'เลนส์แตก') = report,
    'retrying returns the existing report';
  assert (select owner_hidden is false from public.item_tb where id = damaged_item),
    'retrying must respect the lender reopening the listing';

  report := public.rental_return_penalty(lender, late_booking, 'save', false, true, '');
  assert (report->>'amount_satang')::bigint = 5000, 'a late-only report must still apply the agreed fee';
  assert (select owner_hidden is false from public.item_tb where id = late_item),
    'a late-only report must leave the listing visible';
end;
$test$;

rollback;
