begin;

do $test$
declare
  owner_id uuid := gen_random_uuid();
  group_key text := 'read-test:' || owner_id;
  inbox_notice_id uuid;
  already_read_id uuid;
  inbox jsonb;
  violated_rule text;
begin
  assert not exists (
    select 1 from information_schema.columns
    where table_schema='notifications' and table_name='notification_tb' and column_name='is_read'
  ), 'is_read must be derived without a column on the inbox table';

  insert into auth.users(id,email) values (owner_id, owner_id::text||'@example.invalid');
  perform public.notification_register_device(owner_id, group_key, group_key, 'android');
  inbox_notice_id := app_private.notification_emit(owner_id, group_key || ':1', 'app', 'identity_approved',
    'ทดสอบ', 'ทดสอบสถานะอ่าน', p_group_key => group_key);
  perform app_private.notification_emit(owner_id, group_key || ':2', 'app', 'identity_approved',
    'ทดสอบ', 'ทดสอบสถานะอ่าน', p_group_key => group_key);
  already_read_id := app_private.notification_emit(owner_id, group_key || ':already-read', 'app', 'identity_approved',
    'ทดสอบ', 'ทดสอบสถานะอ่าน', p_is_read => true);

  inbox := public.notification_list(owner_id, p_category => 'app');
  assert inbox->'unread_count' = '2'::jsonb;
  assert inbox->'items' @> jsonb_build_array(jsonb_build_object('id', inbox_notice_id, 'is_read', false, 'unread_count', 2));
  assert inbox->'items' @> jsonb_build_array(jsonb_build_object('id', already_read_id, 'is_read', true, 'unread_count', 0));
  assert (select notifications.is_read(n) is false from notifications.notification_tb n where n.id=inbox_notice_id);
  assert (select notifications.is_read(n) is true from notifications.notification_tb n where n.id=already_read_id);
  assert (select count(*) = 2 from notifications.notification_outbox_tb
    where notification_outbox_tb.notification_id = inbox_notice_id
      and payload->'is_read' = 'false'::jsonb), 'unread pushes must retain the boolean payload field';
  assert not exists (select 1 from notifications.notification_outbox_tb where notification_outbox_tb.notification_id=already_read_id);

  begin
    update notifications.notification_tb set read_at=clock_timestamp() where id=inbox_notice_id;
    raise exception 'ต้องปฏิเสธการทำเครื่องหมายอ่านโดยไม่อัปเดตจำนวนที่ยังไม่อ่าน';
  exception when check_violation then
    get stacked diagnostics violated_rule=constraint_name;
    assert violated_rule='notification_read_state_consistent';
  end;

  perform public.notification_mark_read(owner_id, p_id => inbox_notice_id);
  assert exists (select 1 from notifications.notification_tb
    where id=inbox_notice_id and unread_count=0 and read_at is not null);
  inbox := public.notification_list(owner_id);
  assert inbox->'unread_count' = '0'::jsonb;
  assert inbox->'items' @> jsonb_build_array(jsonb_build_object('id', inbox_notice_id, 'is_read', true, 'unread_count', 0));
  assert not exists (select 1 from public.notification_claim_mobile_outbox(100) claimed
    where claimed.notification_id = inbox_notice_id);

  perform app_private.notification_emit(owner_id, group_key || ':3', 'app', 'identity_approved',
    'ทดสอบ', 'ทดสอบสถานะอ่าน', p_group_key => group_key);
  inbox := public.notification_list(owner_id);
  assert inbox->'unread_count' = '1'::jsonb;
  assert inbox->'items' @> jsonb_build_array(jsonb_build_object('id', inbox_notice_id, 'is_read', false, 'unread_count', 1));
  assert exists (select 1 from public.notification_claim_mobile_outbox(100) claimed
    where claimed.notification_id = inbox_notice_id and claimed.payload->'is_read' = 'false'::jsonb);
end
$test$;

rollback;
