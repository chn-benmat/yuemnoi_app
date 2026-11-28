begin;

do $test$
declare
  viewer uuid := gen_random_uuid();
  partner uuid := gen_random_uuid();
  stranger uuid := gen_random_uuid();
  unread_room uuid := gen_random_uuid();
  read_room uuid := gen_random_uuid();
  deleted_sender_room uuid := gen_random_uuid();
  unrequested_room uuid := gen_random_uuid();
  foreign_room uuid := gen_random_uuid();
  result uuid[];
  updated_messages integer;
begin
  insert into auth.users(id,email)
  select u,u::text||'@example.invalid' from unnest(array[viewer,partner,stranger]) u;

  insert into messaging.conversation_tb(id,renter_id,owner_id) values
    (unread_room,viewer,partner),(read_room,viewer,partner),(deleted_sender_room,viewer,partner),
    (unrequested_room,viewer,partner),(foreign_room,stranger,partner);
  insert into messaging.chat_message_tb(conversation_id,sender_id,message,is_read) values
    (unread_room,partner,'ข้อความใหม่ 1',false),(unread_room,partner,'ข้อความใหม่ 2',false),
    (read_room,partner,'อ่านแล้ว',true),(read_room,viewer,'ข้อความที่ส่งเอง',false),
    (deleted_sender_room,null,'ข้อความจากบัญชีที่ลบแล้ว',null),
    (unrequested_room,partner,'ข้อความในห้องนอกชุดที่โหลด',false),
    (foreign_room,partner,'ข้อความในห้องของคนอื่น',false);

  assert not has_function_privilege('anon','public.chat_unread_conversation_ids(uuid[])','execute');
  set local role authenticated;
  perform set_config('request.jwt.claim.sub',viewer::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',viewer,'role','authenticated')::text,true);
  select array_agg(conversation_id order by conversation_id) into result
  from public.chat_unread_conversation_ids(array[unread_room,unread_room,read_room,deleted_sender_room,foreign_room]);
  assert cardinality(result)=2 and result @> array[unread_room,deleted_sender_room],
    'ผลลัพธ์ต้องมีเฉพาะห้องที่ระบุและผู้ใช้มีข้อความค้างอ่าน ห้องละหนึ่งแถว';
  assert not exists (select 1 from public.chat_unread_conversation_ids('{}'::uuid[]));

  update messaging.chat_message_tb m set is_read=true
  where m.conversation_id=any(array[unread_room,read_room,deleted_sender_room,foreign_room])
    and (m.sender_id<>viewer or m.sender_id is null) and m.is_read is not true;
  get diagnostics updated_messages=row_count;
  assert updated_messages=3, 'ต้องเปลี่ยนเฉพาะข้อความค้างอ่านของคู่สนทนาที่ผู้ใช้เข้าถึงได้';
  assert not exists (
    select 1 from public.chat_unread_conversation_ids(array[unread_room,read_room,deleted_sender_room])
  );
end
$test$;

rollback;
