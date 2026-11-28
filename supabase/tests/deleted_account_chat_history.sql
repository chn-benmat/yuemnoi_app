begin;

do $$
declare
  viewer constant uuid := gen_random_uuid();
  departing_owner constant uuid := gen_random_uuid();
  departing_renter constant uuid := gen_random_uuid();
  stranger constant uuid := gen_random_uuid();
  owner_room constant uuid := gen_random_uuid();
  renter_room constant uuid := gen_random_uuid();
  deletion_lease constant uuid := gen_random_uuid();
  recovery_session uuid;
  actor uuid;
  room_id uuid;
  equipment_id bigint;
begin
  insert into auth.users(id, email)
    select id, id || '@example.invalid'
    from unnest(array[viewer, departing_owner, departing_renter, stranger]) id;
  insert into messaging.conversation_tb(id, owner_id, renter_id)
    values (owner_room, departing_owner, viewer), (renter_room, viewer, departing_renter);
  insert into messaging.chat_message_tb(conversation_id, sender_id, message)
    values (owner_room, viewer, 'Viewer message'), (owner_room, departing_owner, 'Former owner message'),
      (renter_room, viewer, 'Viewer message'), (renter_room, departing_renter, 'Former renter message');
  insert into identity_private.identity_profiles(user_id, status, legal_name, masked_id, citizen_hmac, is_minor)
    values (departing_owner, 'approved', 'ผู้ใช้ทดสอบ', '*********1234', md5(departing_owner::text) || md5(departing_owner::text), false);
  update profiles.profile_tb set phone = '0890000001' where user_id = departing_owner;
  insert into public.item_tb(user_id, item_name, description, price, type, status,
    pickup_location, pickup_address, pickup_latitude, pickup_longitude)
    values (departing_owner, 'กล้องทดสอบ', 'อุปกรณ์ทดสอบ', 150, 'รายชั่วโมง', 'available',
      'จุดรับส่วนตัว', 'ที่อยู่ทดสอบ', 13.75, 100.5)
    returning id into equipment_id;
  update messaging.conversation_tb set item_id = equipment_id where id = owner_room;
  insert into messaging.chat_message_tb(conversation_id, sender_id, message)
    values (owner_room, departing_owner, format(
      E'📋 คำขอเช่าอุปกรณ์\nสถานที่นัดพบ: จุดรับส่วนตัว\nห้องทดสอบ\nยอดรวม: 150 ฿\n[BOOKING_DATA:{"itemId":%s}]', equipment_id));
  insert into messaging.chat_message_tb(conversation_id, sender_id, message, image_url)
    values (owner_room, departing_owner, '', 'https://example.invalid/deleted.jpg'),
      (renter_room, viewer, '', 'https://example.invalid/retained.jpg');

  foreach actor in array array[departing_owner, departing_renter] loop
    room_id := case actor when departing_owner then owner_room else renter_room end;
    perform public.account_deletion_schedule(actor);

    set local role authenticated;
    perform set_config('request.jwt.claim.sub', viewer::text, true);
    perform set_config('request.jwt.claims', jsonb_build_object('sub', viewer, 'role', 'authenticated')::text, true);
    assert exists (select 1 from messaging.conversation_tb where id = room_id),
      'The surviving participant cannot see the room during the grace period';
    assert (select count(*) = case actor when departing_owner then 4 else 3 end
      from messaging.chat_message_tb where conversation_id = room_id);
    assert not exists (select 1 from profiles.public_profile_v where user_id = actor);
    begin
      insert into messaging.chat_message_tb(conversation_id, sender_id, message)
        values (room_id, viewer, 'Unexpected new message');
      raise exception 'Sent a message to an account pending deletion';
    exception when insufficient_privilege then null;
    end;

    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
    recovery_session := gen_random_uuid();
    insert into auth.sessions(id, user_id, created_at) values (recovery_session, actor, clock_timestamp());
    perform public.account_deletion_restore(actor, recovery_session);
    assert exists (select 1 from profiles.public_profile_v where user_id = actor);
    perform public.account_deletion_schedule(actor);
    update app_private.account_deletions set requested_at = now() - interval '31 days',
      delete_after = now() - interval '1 day', lease_token = deletion_lease,
      lease_until = now() + interval '5 minutes' where user_id = actor;
    perform public.account_deletion_complete(actor, deletion_lease);
    assert not exists (select 1 from auth.users where id = actor);
    assert not exists (select 1 from profiles.profile_tb where user_id = actor);
    assert exists (select 1 from messaging.conversation_tb where id = room_id and
      ((renter_id = viewer and owner_id is null) or (owner_id = viewer and renter_id is null))),
      'The room was not retained with an anonymous participant';
    assert (select count(*) = case actor when departing_owner then 4 else 3 end
      from messaging.chat_message_tb where conversation_id = room_id);
    assert exists (select 1 from messaging.chat_message_tb where conversation_id = room_id
      and sender_id is null and message = case actor when departing_owner then 'Former owner message' else 'Former renter message' end);
    assert exists (select 1 from messaging.chat_message_tb where conversation_id = room_id
      and sender_id = viewer and message = 'Viewer message');
  end loop;

  assert exists (select 1 from messaging.chat_message_tb where conversation_id = owner_room
    and sender_id is null and message = '[รูปภาพถูกลบ]' and image_url is null);
  assert exists (select 1 from messaging.chat_message_tb where conversation_id = owner_room
    and sender_id is null and message = E'ข้อเสนอการเช่าเดิม\nยอดรวม: 150 ฿');
  assert not exists (select 1 from app_private.pickup_offer_snapshot where conversation_id = owner_room);
  assert exists (select 1 from messaging.chat_message_tb where conversation_id = renter_room
    and sender_id = viewer and image_url = 'https://example.invalid/retained.jpg');

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', stranger::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', stranger, 'role', 'authenticated')::text, true);
  assert not exists (select 1 from messaging.conversation_tb where id in (owner_room, renter_room));
  assert not exists (select 1 from messaging.chat_message_tb where conversation_id in (owner_room, renter_room));

  perform set_config('request.jwt.claim.sub', viewer::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', viewer, 'role', 'authenticated')::text, true);
  assert (select count(*) = 2 from messaging.conversation_tb where id in (owner_room, renter_room));
  assert (select count(*) = 7 from messaging.chat_message_tb where conversation_id in (owner_room, renter_room));
  begin
    insert into messaging.chat_message_tb(conversation_id, sender_id, message)
      values (owner_room, viewer, 'Unexpected new message');
    raise exception 'Sent a message to a deleted account';
  exception when insufficient_privilege then null;
  end;
  begin
    update messaging.conversation_tb set owner_id = stranger where id = owner_room;
    raise exception 'A member replaced the deleted participant';
  exception when insufficient_privilege then null;
  end;
  begin
    update messaging.chat_message_tb set sender_id = viewer where conversation_id = owner_room and sender_id is null;
    raise exception 'A member replaced the author of a retained message';
  exception when insufficient_privilege then null;
  end;
  update messaging.chat_message_tb set is_read = true where conversation_id = owner_room and sender_id is null;
  assert (select bool_and(is_read) from messaging.chat_message_tb where conversation_id = owner_room and sender_id is null);

  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform public.account_deletion_schedule(viewer);
  update app_private.account_deletions set requested_at = now() - interval '31 days',
    delete_after = now() - interval '1 day', lease_token = deletion_lease,
    lease_until = now() + interval '5 minutes' where user_id = viewer;
  perform public.account_deletion_complete(viewer, deletion_lease);
  assert not exists (select 1 from messaging.conversation_tb where id in (owner_room, renter_room));
  assert not exists (select 1 from messaging.chat_message_tb where conversation_id in (owner_room, renter_room));
end
$$;

rollback;
