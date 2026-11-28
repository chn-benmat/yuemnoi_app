begin;

-- กัน topic นี้ไว้ให้ worker แม้มี policy Realtime สำหรับผู้ใช้เพิ่มภายหลัง
create policy notification_outbox_server_topic on realtime.messages
as restrictive for all to anon, authenticated
using (
  topic is distinct from 'notification-outbox'
  and (select realtime.topic()) is distinct from 'notification-outbox'
)
with check (
  topic is distinct from 'notification-outbox'
  and (select realtime.topic()) is distinct from 'notification-outbox'
);

create function app_private.wake_notification_outbox()
returns trigger
language plpgsql security definer
set search_path to ''
as $$
declare
  previous_topic text := current_setting('realtime.topic', true);
begin
  -- งานจริงเก็บใน outbox และใช้ lease เดิม ฝั่ง Realtime ส่งเพียงสัญญาณหลัง commit
  if exists (select 1 from new_deliveries) then
    perform realtime.send('{}'::jsonb, 'outbox_ready', 'notification-outbox', true);
    perform set_config('realtime.topic', coalesce(previous_topic, ''), true);
  end if;
  return null;
end;
$$;

revoke all on function app_private.wake_notification_outbox()
from public, anon, authenticated, service_role;

create trigger notification_outbox_realtime
after insert on notifications.notification_outbox_tb
referencing new table as new_deliveries
for each statement execute function app_private.wake_notification_outbox();

commit;
