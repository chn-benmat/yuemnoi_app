begin isolation level repeatable read;

do $test$
declare
  recipient_id uuid := gen_random_uuid();
  no_device_id uuid := gen_random_uuid();
  v_event_key text := 'notification-realtime-test:' || recipient_id;
  before_count integer;
begin
  insert into auth.users(id, email) values
    (recipient_id, recipient_id || '@example.invalid'),
    (no_device_id, no_device_id || '@example.invalid');
  perform public.notification_register_device(recipient_id, recipient_id || '-android', recipient_id || '-token-1', 'android');
  perform public.notification_register_device(recipient_id, recipient_id || '-ios', recipient_id || '-token-2', 'ios');

  select count(*) into before_count from realtime.messages where topic = 'notification-outbox';
  perform set_config('realtime.topic', 'existing-topic', true);
  perform app_private.notification_emit(recipient_id, v_event_key, 'app', 'identity_approved', 'ทดสอบ', 'ข้อมูลสำหรับประวัติ');
  assert (select count(*) = 2 from notifications.notification_outbox_tb o where o.event_key = v_event_key),
    'both devices must have a queued delivery';
  assert (select count(*) = before_count + 1 from realtime.messages m where m.topic = 'notification-outbox'
    and m.event = 'outbox_ready' and m.private and m.extension = 'broadcast' and (m.payload - 'id') = '{}'::jsonb),
    'one private wakeup with no event contents must be added for the batch';
  assert realtime.topic() = 'existing-topic', 'the trigger must restore the original topic';

  perform app_private.notification_emit(recipient_id, v_event_key, 'app', 'identity_approved', 'ทดสอบ', 'ข้อความเดิม');
  perform app_private.notification_emit(no_device_id, v_event_key || ':no-device', 'app', 'identity_approved', 'ทดสอบ', 'ไม่มีเครื่อง');
  assert (select count(*) = before_count + 1 from realtime.messages where topic = 'notification-outbox'),
    'deduplicated events and empty outbox inserts must not broadcast';
end;
$test$;

rollback;
