begin;

create function app_private.notification_mobile_type(p_type text)
returns boolean
language sql immutable
set search_path to ''
as $$
  select p_type in ('chat_message', 'rental_request_received', 'rental_queue_ready',
    'rental_due_1h', 'rental_due_30m', 'rental_review_pending', 'item_approved', 'identity_approved');
$$;

create index if not exists notification_active_booking_due_idx on public.booking_tb(end_at, id)
where status in ('active', 'awaiting_return', 'return_ready') and user_id is not null;

create index if not exists notification_queue_ready_message_idx on app_private.rental_queue(ready_message_id)
where ready_message_id is not null;

-- ให้ worker รุ่นนี้เริ่มส่งได้เมื่อฐานข้อมูลใช้กฎแจ้งเตือนชุดเดียวกันแล้ว
alter function public.notification_schedule_reminders(timestamptz) rename to notification_schedule_mobile_reminders;
alter function public.notification_claim_outbox(integer, integer) rename to notification_claim_mobile_outbox;

create or replace function public.notification_schedule_mobile_reminders(p_now timestamptz default now())
returns integer
language plpgsql
set search_path to ''
as $$
declare
  reminder record;
  count_added integer := 0;
begin
  for reminder in
    select b.id, b.user_id, b.item_id, b.end_at, i.item_name, timing.kind,
      timing.expires_at, key.event_key
    from public.booking_tb b
    join public.item_tb i on i.id = b.item_id
    cross join lateral (
      select case when b.end_at > p_now + interval '30 minutes' then '1h' else '30m' end as kind,
        case when b.end_at > p_now + interval '30 minutes' then b.end_at - interval '30 minutes' else b.end_at end as expires_at
    ) timing
    cross join lateral (
      select 'return-reminder:' || b.id || ':' || extract(epoch from b.end_at) || ':' || timing.kind as event_key
    ) key
    where b.status in ('active', 'awaiting_return', 'return_ready') and b.user_id is not null
      and b.end_at > p_now and b.end_at <= p_now + interval '1 hour'
      and not app_private.account_deletion_pending(b.user_id)
      and not exists (select 1 from app_private.notification_event_tb e where e.event_key = key.event_key)
    order by b.end_at, b.id limit 500
  loop
    if app_private.notification_emit(reminder.user_id, reminder.event_key, 'rental',
      'rental_due_' || reminder.kind, 'ใกล้ถึงเวลาคืนสินค้า',
      format('กรุณาเตรียมคืน %s ภายใน %s น.', reminder.item_name,
        to_char(reminder.end_at at time zone 'Asia/Bangkok', 'HH24:MI')),
      jsonb_build_object('booking_id', reminder.id, 'item_id', reminder.item_id,
        'reminder', true, 'due_at', reminder.end_at, 'destination', '/profile/rental-status'),
      p_expires_at => reminder.expires_at) is not null
    then
      count_added := count_added + 1;
    end if;
  end loop;
  return count_added;
end;
$$;

create function app_private.notify_mobile_rental()
returns trigger
language plpgsql security definer
set search_path to ''
as $$
declare
  rental public.booking_tb;
  item public.item_tb;
  room_id uuid;
begin
  if tg_op = 'UPDATE' then
    if new.status = 'completed' and old.status is distinct from new.status and new.user_id is not null
      and not exists (select 1 from public.review_tb r where r.booking_id = new.id and r.user_id = new.user_id)
    then
      select * into item from public.item_tb where id = new.item_id;
      perform app_private.notification_emit(new.user_id, 'review-reminder:' || new.id, 'rental',
        'rental_review_pending', 'ให้คะแนนสินค้าที่คืนแล้ว', coalesce(item.item_name, 'รายการเช่าของคุณ'),
        jsonb_build_object('booking_id', new.id, 'item_id', new.item_id, 'destination', '/profile/rental-history'));
    end if;
    return null;
  end if;

  -- คำขอในแชทมีข้อความที่เชื่อมกับรายการและแจ้งผ่าน trigger ของข้อความ
  select * into rental from public.booking_tb where id = new.id and status = 'pending'
    and rental_request_message_id is null;
  if not found or rental.user_id is null then return null; end if;
  select * into item from public.item_tb where id = rental.item_id;
  if item.user_id is null or item.user_id = rental.user_id then return null; end if;
  select c.id into room_id from messaging.conversation_tb c
  where c.item_id = item.id and ((c.renter_id = rental.user_id and c.owner_id = item.user_id)
    or (c.owner_id = rental.user_id and c.renter_id = item.user_id))
  order by c.updated_at desc nulls last, c.id limit 1;
  perform app_private.notification_emit(item.user_id, 'rental-request:' || rental.id, 'rental',
    'rental_request_received', 'มีคำขอเช่าใหม่', item.item_name,
    jsonb_build_object('booking_id', rental.id, 'item_id', item.id, 'conversation_id', room_id,
      'booking_status', 'pending', 'destination', '/profile/rental-status?role=lender'));
  return null;
end;
$$;

create trigger booking_notify_review_pending
after update of status on public.booking_tb
for each row execute function app_private.notify_mobile_rental();

create constraint trigger booking_notify_mobile_request
after insert on public.booking_tb deferrable initially deferred
for each row execute function app_private.notify_mobile_rental();

create function app_private.notify_mobile_item_approval()
returns trigger
language plpgsql security definer
set search_path to ''
as $$
declare
  item public.item_tb;
begin
  select * into item from public.item_tb where id = new.target::bigint and status = 'available';
  if found and item.user_id is not null then
    perform app_private.notification_emit(item.user_id, 'item-approved:' || new.id, 'app',
      'item_approved', 'แอดมินอนุมัติประกาศสินค้าแล้ว', item.item_name,
      jsonb_build_object('item_id', item.id, 'destination', '/profile/my-items'));
  end if;
  return null;
end;
$$;

create trigger staff_audit_notify_item_approval
after insert on ops_private.staff_audit for each row when (new.action = 'item-review-approved')
execute function app_private.notify_mobile_item_approval();

create or replace function app_private.notification_chat_event()
returns trigger
language plpgsql security definer
set search_path to ''
as $$
declare
  room messaging.conversation_tb;
  current_message messaging.chat_message_tb;
  queue_entry app_private.rental_queue;
  rental public.booking_tb;
  recipient uuid;
  sender_name text;
  item_name text;
  preview text;
  count_unread integer;
begin
  select * into room from messaging.conversation_tb where id = new.conversation_id;
  recipient := case new.sender_id when room.renter_id then room.owner_id when room.owner_id then room.renter_id end;
  if recipient is null or recipient = new.sender_id then return new; end if;

  if tg_op = 'UPDATE' then
    if new.is_read is distinct from old.is_read then
      select count(*) into count_unread from messaging.chat_message_tb m
      where m.conversation_id = new.conversation_id and m.sender_id = new.sender_id and not coalesce(m.is_read, false);
      update notifications.notification_tb set unread_count = count_unread, is_read = count_unread = 0,
        read_at = case when count_unread = 0 then clock_timestamp() end
      where user_id = recipient and conversation_id = new.conversation_id and type = 'chat_message';
      if new.is_read then
        update notifications.notification_tb set unread_count = 0, is_read = true, read_at = clock_timestamp()
        where event_key = 'rental-request-message:' || new.id || ':' || recipient;
      end if;
    end if;
    return new;
  end if;

  select * into current_message from messaging.chat_message_tb where id = new.id;
  if not found then return new; end if;
  -- ข้อความกับการ์ดคิวเชื่อมกันใน transaction เดียวกันก่อน trigger แบบ deferred ทำงาน
  select * into queue_entry from app_private.rental_queue q
  where q.conversation_id = new.conversation_id and q.ready_message_id = new.id;
  if found then
    select i.item_name into item_name from public.item_tb i where i.id = queue_entry.item_id;
    if queue_entry.status = 'ready' and queue_entry.expires_at > clock_timestamp() then
      perform app_private.notification_emit(queue_entry.renter_id, 'rental-queue-ready:' || new.id, 'rental',
        'rental_queue_ready', 'ถึงคิวเช่าสินค้าของคุณแล้ว',
        format('%s พร้อมให้เช่า กรุณายืนยันสิทธิ์ภายใน 24 ชั่วโมง', item_name),
        jsonb_build_object('conversation_id', new.conversation_id, 'item_id', queue_entry.item_id,
          'queue_id', queue_entry.id, 'queue_message_id', new.id, 'destination', '/chat/detail'),
        p_expires_at => queue_entry.expires_at);
    end if;
    return new;
  end if;

  select * into rental from public.booking_tb where rental_request_message_id = new.id;
  if found then
    select i.item_name into item_name from public.item_tb i where i.id = rental.item_id and i.user_id = recipient;
    if found and rental.status = 'pending' then
      perform app_private.notification_emit(recipient, 'rental-request-message:' || new.id || ':' || recipient,
        'chat', 'rental_request_received', 'มีคำขอเช่าใหม่', item_name,
        jsonb_build_object('conversation_id', new.conversation_id, 'message_id', new.id, 'booking_id', rental.id,
          'item_id', rental.item_id, 'booking_status', 'pending', 'destination', '/chat/detail'),
        p_is_read => coalesce(current_message.is_read, false));
    end if;
    return new;
  end if;

  select p.display_name into sender_name from profiles.profile_tb p where p.user_id = new.sender_id;
  preview := case
    when coalesce(btrim(current_message.message), '') = '' and current_message.image_url is not null then 'ส่งรูปภาพถึงคุณ'
    when current_message.message like '{%' or current_message.message like '%[BOOKING_DATA:%' then 'ส่งข้อมูลรายการเช่าถึงคุณ'
    else coalesce(nullif(btrim(current_message.message), ''), 'ส่งข้อความถึงคุณ')
  end;
  perform app_private.notification_emit(recipient, 'chat-message:' || new.id || ':' || recipient,
    'chat', 'chat_message', coalesce(nullif(sender_name, ''), 'ข้อความใหม่'), preview,
    jsonb_build_object('conversation_id', new.conversation_id, 'message_id', new.id,
      'sender_id', new.sender_id, 'item_id', room.item_id, 'destination', '/chat/detail'),
    'chat:' || new.conversation_id || ':' || recipient, coalesce(current_message.is_read, false));
  return new;
end;
$$;

drop trigger chat_30_notification on messaging.chat_message_tb;
create trigger chat_30_notification after update of is_read on messaging.chat_message_tb
for each row execute function app_private.notification_chat_event();
create constraint trigger chat_mobile_notification after insert on messaging.chat_message_tb
deferrable initially deferred for each row execute function app_private.notification_chat_event();

revoke all on function app_private.notify_mobile_rental(), app_private.notify_mobile_item_approval()
from public, anon, authenticated, service_role;
revoke all on function app_private.notification_mobile_type(text) from public, anon, authenticated;
grant execute on function app_private.notification_mobile_type(text) to service_role;


CREATE OR REPLACE FUNCTION app_private.notification_emit(p_user_id uuid, p_event_key text, p_category text, p_type text, p_title text, p_body text, p_data jsonb DEFAULT '{}'::jsonb, p_group_key text DEFAULT NULL::text, p_is_read boolean DEFAULT false, p_push boolean DEFAULT true, p_expires_at timestamp with time zone DEFAULT (now() + '24:00:00'::interval))
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v notifications.notification_tb; v_now timestamptz:=clock_timestamp(); v_inserted integer;
begin
 if p_user_id is null then return null; end if;
 insert into app_private.notification_event_tb(event_key,user_id,conversation_id,message_id,created_at)
 values(p_event_key,p_user_id,nullif(p_data->>'conversation_id','')::uuid,nullif(p_data->>'message_id','')::bigint,v_now)
 on conflict do nothing;
 get diagnostics v_inserted=row_count;
 if v_inserted=0 then return null; end if;
 insert into notifications.notification_tb(user_id,event_key,category,type,title,body,conversation_id,booking_id,item_id,data,is_read,unread_count,created_at,updated_at,read_at)
 values(p_user_id,coalesce(p_group_key,p_event_key),p_category,p_type,p_title,left(p_body,300),nullif(p_data->>'conversation_id','')::uuid,
 nullif(p_data->>'booking_id','')::bigint,nullif(p_data->>'item_id','')::bigint,
 p_data||jsonb_build_object('event_key',p_event_key,'recipient_id',p_user_id,'event_at',v_now),p_is_read,case when p_is_read then 0 else 1 end,v_now,v_now,case when p_is_read then v_now end)
 on conflict(event_key) do update set title=excluded.title,body=excluded.body,data=excluded.data,
 updated_at=excluded.updated_at,is_read=excluded.is_read,read_at=excluded.read_at,
 unread_count=case when excluded.is_read then 0 else notifications.notification_tb.unread_count+1 end
 returning * into v;
 if p_push and not p_is_read and app_private.notification_mobile_type(p_type)
   and not app_private.account_deletion_pending(p_user_id) then
  insert into notifications.notification_outbox_tb(notification_id,device_id,event_key,payload,expires_at)
  select v.id,d.id,p_event_key,to_jsonb(v),p_expires_at from notifications.notification_device_tb d where d.user_id=p_user_id and d.enabled
  on conflict do nothing;
 end if;
 return v.id;
end $function$;

CREATE OR REPLACE FUNCTION app_private.notification_system_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid; v_type text; v_title text; v_body text:='เปิดแอปเพื่อดูรายละเอียด'; v_data jsonb:='{}'; v_new jsonb:=to_jsonb(new); v_old jsonb:=to_jsonb(old);
begin
 if tg_table_name='identity_requests' and v_new->>'status' is distinct from v_old->>'status' and v_new->>'status' in ('approved','rejected','corrections') then
  v_user:=(v_new->>'user_id')::uuid;v_type:='identity_'||(v_new->>'status');v_title:=case when v_type='identity_approved' then 'ยืนยันบัตรประชาชนผ่านแล้ว' else 'ผลการยืนยันตัวตนมีการอัปเดต' end;
  v_data:=jsonb_build_object('destination','/setting/identity');
 elsif tg_table_name='identity_profiles' and v_old->>'status'='approved' and v_new->>'status' is distinct from v_old->>'status' then
  v_user:=(v_new->>'user_id')::uuid;v_type:='identity_revoked';v_title:='สถานะการยืนยันตัวตนเปลี่ยนแปลง';v_data:=jsonb_build_object('destination','/profile/identity');
 elsif tg_table_name='account_controls' and coalesce((v_new->>'suspended')::boolean,false) is distinct from coalesce((v_old->>'suspended')::boolean,false) then
  v_user:=(v_new->>'user_id')::uuid;v_type:=case when (v_new->>'suspended')::boolean then 'account_suspended' else 'account_restored' end;v_title:='สิทธิ์การใช้งานบัญชีมีการอัปเดต';v_data:=jsonb_build_object('destination','/profile/identity');
 elsif tg_table_name in ('item_tb','review_tb') and v_new->>'moderation_hidden' is distinct from v_old->>'moderation_hidden' then
  v_user:=(v_new->>'user_id')::uuid;v_type:=case when tg_table_name='item_tb' then 'item_' else 'review_' end||case when (v_new->>'moderation_hidden')::boolean then 'hidden' else 'restored' end;
  v_title:=case when tg_table_name='item_tb' then 'สถานะประกาศสินค้ามีการอัปเดต' else 'สถานะรีวิวมีการอัปเดต' end;
  v_data:=jsonb_build_object('destination',case when tg_table_name='item_tb' then '/profile/my-items' else '/notifications' end);
 elsif tg_table_name='complaints' and v_new->>'status' is distinct from v_old->>'status' then
  v_user:=(v_new->>'reporter_id')::uuid;v_type:='complaint_'||(v_new->>'status');v_title:='เรื่องร้องเรียนของคุณมีความคืบหน้า';v_data:=jsonb_build_object('destination','/notifications');
 end if;
 if v_user is not null then perform app_private.notification_emit(v_user,'system:'||tg_table_name||':'||coalesce(v_new->>'id',v_user::text)||':'||clock_timestamp()::text,'app',v_type,v_title,v_body,v_data); end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION public.notification_claim_mobile_outbox(p_limit integer DEFAULT 20, p_lease_seconds integer DEFAULT 120)
 RETURNS TABLE(id uuid, lease_token uuid, device_id uuid, user_id uuid, token text, notification_id uuid, payload jsonb, expires_at timestamp with time zone)
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 -- งานที่ worker ล่มหลังส่งต้องนับรวมในเพดาน retry เมื่อ lease สิ้นสุดด้วย
 update notifications.notification_outbox_tb o set status='failed',last_error='retry_exhausted',lease_until=null,lease_token=null,delivery_token=null
 where o.attempts>=8 and (o.status='pending' or (o.status='processing' and o.lease_until<clock_timestamp()));
 -- งานค้างที่หมดความเกี่ยวข้องหรือถูกอ่านแล้วไม่ควรเด้งย้อนหลัง
 update notifications.notification_outbox_tb o set status='failed',last_error='obsolete'
 where o.status in ('pending','processing') and (o.expires_at<=clock_timestamp()
 or not app_private.notification_mobile_type(o.payload->>'type')
 or not exists(select 1 from notifications.notification_device_tb d join notifications.notification_tb n on n.id=o.notification_id
  where d.id=o.device_id and d.enabled and d.user_id=n.user_id and not app_private.account_deletion_pending(n.user_id))
 or (o.payload->>'category'='chat' and not exists(select 1 from messaging.chat_message_tb m
  where m.id=nullif(o.payload->'data'->>'message_id','')::bigint and m.conversation_id=nullif(o.payload->>'conversation_id','')::uuid and not coalesce(m.is_read,false)))
 or (o.payload->'data'->>'reminder'='true' and not exists(select 1 from public.booking_tb b where b.id=(o.payload->>'booking_id')::bigint and b.status in ('active','awaiting_return','return_ready')
  and b.end_at=(o.payload->'data'->>'due_at')::timestamptz))
 or (o.payload->>'type'='rental_request_received' and o.payload->'data'->>'booking_status' is not null
  and not exists(select 1 from public.booking_tb b where b.id=(o.payload->>'booking_id')::bigint and b.status=o.payload->'data'->>'booking_status'))
 or (o.payload->>'type'='rental_review_pending' and not exists(
  select 1 from public.booking_tb b where b.id=(o.payload->>'booking_id')::bigint and b.status='completed'
    and not exists(select 1 from public.review_tb r where r.booking_id=b.id and r.user_id=b.user_id)))
 or (o.payload->>'type'='rental_queue_ready' and not exists(
  select 1 from app_private.rental_queue q where q.id=(o.payload->'data'->>'queue_id')::bigint
    and q.ready_message_id=(o.payload->'data'->>'queue_message_id')::bigint and q.status='ready'
    and q.expires_at>clock_timestamp()))
 or exists(select 1 from notifications.notification_tb n where n.id=o.notification_id and n.is_read));
 return query with jobs as (
  select o.id from notifications.notification_outbox_tb o
  join notifications.notification_device_tb d on d.id=o.device_id
  join notifications.notification_tb n on n.id=o.notification_id
  where app_private.notification_mobile_type(o.payload->>'type') and d.enabled and d.user_id=n.user_id and not n.is_read and o.expires_at>clock_timestamp() and o.attempts<8
  and ((o.status='pending' and o.available_at<=clock_timestamp()) or (o.status='processing' and o.lease_until<clock_timestamp()))
  order by o.available_at limit least(greatest(p_limit,1),100) for update of o skip locked
 ), claimed as (
  update notifications.notification_outbox_tb o set status='processing',attempts=o.attempts+1,lease_token=gen_random_uuid(),lease_until=clock_timestamp()+make_interval(secs=>least(greatest(p_lease_seconds,30),300)),delivery_token=d.token
  from jobs j,notifications.notification_device_tb d,notifications.notification_tb n
  where o.id=j.id and d.id=o.device_id and n.id=o.notification_id and d.enabled and d.user_id=n.user_id
  returning o.id,o.lease_token,o.device_id,n.user_id,d.token,o.notification_id,o.payload,o.expires_at
 ) select * from claimed;
end $function$;

CREATE OR REPLACE FUNCTION public.notification_list(p_user_id uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_category text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_time timestamptz:=clock_timestamp(); v_items jsonb; v_count bigint;
begin
 select coalesce(jsonb_agg(to_jsonb(n) order by n.updated_at desc,n.id),'[]'::jsonb) into v_items from
 (select * from notifications.notification_tb where user_id=p_user_id and app_private.notification_mobile_type(type) and (p_category is null or category=p_category)
 order by updated_at desc,id limit least(greatest(p_limit,1),100) offset greatest(p_offset,0)) n;
 select coalesce(sum(unread_count),0) into v_count from notifications.notification_tb where user_id=p_user_id and app_private.notification_mobile_type(type) and not is_read and (p_category is null or category=p_category);
 return jsonb_build_object('items',v_items,'unread_count',v_count,'server_time',v_time);
end $function$;

revoke execute on function public.notification_schedule_mobile_reminders(timestamptz),
  public.notification_claim_mobile_outbox(integer, integer) from public, anon, authenticated;
grant execute on function public.notification_schedule_mobile_reminders(timestamptz),
  public.notification_claim_mobile_outbox(integer, integer) to service_role;

commit;
