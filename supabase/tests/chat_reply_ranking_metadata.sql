begin;

do $test$
declare
  customer uuid := gen_random_uuid();
  merchant uuid := gen_random_uuid();
  outsider uuid := gen_random_uuid();
  room uuid := gen_random_uuid();
  listed bigint;
  unrelated bigint;
  inquiry bigint;
  reply bigint;
  received timestamptz;
  card text;
begin
  assert exists (select 1 from information_schema.columns
    where table_schema = 'messaging' and table_name = 'chat_message_tb' and column_name = 'server_received_at'),
    'Chat messages must have a server receipt timestamp';
  insert into auth.users(id, email)
    select u, u || '@example.invalid' from unnest(array[customer, merchant, outsider]) u;
  insert into public.item_tb(user_id, item_name, description, price, status, type,
    pickup_location, pickup_address, pickup_note, pickup_latitude, pickup_longitude)
    values (merchant, 'Tripod', 'Test', 150, 'available', 'daily', 'Test', 'Test', 'Test', 13.75, 100.50)
    returning id into listed;
  insert into public.item_tb(user_id, item_name, description, price, status, type,
    pickup_location, pickup_address, pickup_note, pickup_latitude, pickup_longitude)
    values (outsider, 'Lens', 'Test', 150, 'available', 'daily', 'Test', 'Test', 'Test', 13.75, 100.50)
    returning id into unrelated;
  -- This account pair already had a room with the opposite roles.
  insert into messaging.conversation_tb(id, owner_id, renter_id) values (room, customer, merchant);
  insert into public.item_auto_reply_tb(item_id, enabled, message) values (listed, true, 'Available.')
    on conflict (item_id) do update set enabled = true, message = excluded.message;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', customer::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', customer, 'role', 'authenticated')::text, true);
  card := format(E'ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:\nอุปกรณ์: Tripod\n[ITEM_INQUIRY:{"itemId":%s}]', listed);
  insert into messaging.chat_message_tb(conversation_id, sender_id, message, created_at, server_received_at,
    message_kind, inquiry_item_id, inquiry_owner_id)
    values (room, customer, card, '1990-01-01', '2030-01-01', 'manual', unrelated, outsider)
    returning id, server_received_at into inquiry, received;
  assert received between transaction_timestamp() and clock_timestamp();
  assert exists (select from messaging.chat_message_tb where id = inquiry and message_kind = 'inquiry'
    and inquiry_item_id = listed and inquiry_owner_id = merchant and created_at = '1990-01-01');
  assert exists (select from messaging.chat_message_tb where conversation_id = room and message = 'Available.'
    and sender_id = merchant and message_kind = 'auto_reply' and server_received_at >= received);

  insert into messaging.chat_message_tb(conversation_id, sender_id, message) values
    (room, customer, replace(card, listed::text || '}', unrelated::text || '}')),
    (room, customer, E'ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:\n[ITEM_INQUIRY:{broken}]'),
    (room, customer, E'ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:\n[ITEM_INQUIRY:{"itemId":"bad"}]'),
    (room, customer, E'ฉันสนใจเช่าอุปกรณ์ของคุณตามรายละเอียดนี้:\nอุปกรณ์: Tripod');
  assert (select count(*) = 4 from messaging.chat_message_tb where conversation_id = room
    and sender_id = customer and message_kind = 'unknown' and inquiry_item_id is null and inquiry_owner_id is null);

  perform set_config('request.jwt.claim.sub', merchant::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', merchant, 'role', 'authenticated')::text, true);
  insert into messaging.chat_message_tb(conversation_id, sender_id, message, message_kind)
    values (room, merchant, 'Available.', 'auto_reply') returning id into reply;
  assert exists (select from messaging.chat_message_tb where id = reply and message_kind = 'manual');
  insert into messaging.chat_message_tb(conversation_id, sender_id, message, image_url) values
    (room, merchant, '', 'https://example.invalid/tripod.jpg'),
    (room, merchant, E'↩ ตอบกลับ:Customer|อุปกรณ์: Tripod|1|\nYes', null),
    (room, merchant, card, null);
  assert (select count(*) = 3 from messaging.chat_message_tb where conversation_id = room
    and sender_id = merchant and message_kind = 'manual');
  assert exists (select from messaging.chat_message_tb where conversation_id = room
    and sender_id = merchant and message = card and message_kind = 'unknown');
  update messaging.chat_message_tb set message = 'Edited reply', message_kind = 'auto_reply' where id = reply;
  update messaging.chat_message_tb set is_read = true, message_kind = 'manual', server_received_at = '1990-01-01',
    inquiry_item_id = unrelated, inquiry_owner_id = outsider where id = inquiry;
  assert exists (select from messaging.chat_message_tb where id = reply and message = 'Edited reply' and message_kind = 'manual');
  assert exists (select from messaging.chat_message_tb where id = inquiry and is_read and server_received_at = received
    and message_kind = 'inquiry' and inquiry_item_id = listed and inquiry_owner_id = merchant);

  reset role;
  -- A server-created card can carry the same sender ID as the JWT, e.g. inside a definer RPC.
  insert into messaging.chat_message_tb(conversation_id, sender_id, message)
    values (room, merchant, '{"rentalQueue":{}}'), (room, merchant, 'Server generated notice');
  assert exists (select from messaging.chat_message_tb where conversation_id = room
    and message = '{"rentalQueue":{}}' and message_kind = 'system');
  assert exists (select from messaging.chat_message_tb where conversation_id = room
    and message = 'Server generated notice' and message_kind = 'unknown');

  -- Account deletion keeps the other participant's chat history after detaching
  -- the departing account from its messages, room, and listings.
  update messaging.chat_message_tb set sender_id = null where sender_id = merchant;
  update messaging.conversation_tb set renter_id = null where id = room;
  delete from public.item_tb where id = listed;
  delete from auth.users where id = merchant;
  assert exists (select from messaging.chat_message_tb where id = inquiry and inquiry_owner_id is null
    and server_received_at = received), 'Retained chat must release a permanently deleted owner ID';
end;
$test$;

rollback;
