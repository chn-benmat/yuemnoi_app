begin;

do $$
declare
  viewer uuid := gen_random_uuid();
  other_viewer uuid := gen_random_uuid();
  equipment_id bigint;
  last_view_count bigint;
  score_without_view double precision;
  score_with_view double precision;
begin
  assert to_regclass('public.user_item_events') is null,
    'ตารางเหตุการณ์เดิมยังอยู่หลังย้าย';
  assert not has_table_privilege('authenticated', 'public.user_item_views', 'INSERT'),
    'แอปสามารถเขียนเวลาดูโดยข้าม RPC';
  assert not has_function_privilege('anon', 'public.record_item_view_event(bigint)', 'EXECUTE'),
    'ผู้เยี่ยมชมสามารถเรียก RPC บันทึกประวัติ';

  insert into auth.users(id, email)
    values (viewer, viewer::text || '@example.invalid'),
           (other_viewer, other_viewer::text || '@example.invalid');
  insert into identity_private.identity_profiles(user_id, status, legal_name, masked_id, citizen_hmac, is_minor)
    values (other_viewer, 'approved', 'ผู้ใช้ทดสอบ', '*********1234',
      md5(other_viewer::text) || md5(other_viewer::text), false);
  update profiles.profile_tb set phone = '0812345678' where user_id = other_viewer;
  insert into public.item_tb(user_id, item_name, description, status, category, pickup_location, pickup_address, pickup_latitude, pickup_longitude, hourly_rate, daily_rate)
    values (other_viewer, 'กล้องทดสอบ', 'อุปกรณ์ทดสอบ', 'available', 'กล้อง',
      'จุดรับ', 'ที่อยู่ทดสอบ', 13.75, 100.5, 150, null)
    returning id into equipment_id;

  set local role anon;
  assert exists (select 1 from public.home_feed_ranked_v where id = equipment_id),
    'ผู้เยี่ยมชมต้องอ่านฟีดได้';
  assert not exists (select 1 from public.user_item_views),
    'ผู้เยี่ยมชมอ่านประวัติได้';
  reset role;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', viewer::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', viewer, 'role', 'authenticated', 'is_anonymous', false)::text, true);
  select rank_score into score_without_view from public.home_feed_ranked_v
    where id = equipment_id;

  assert public.record_item_view_event(equipment_id), 'บันทึกการดูครั้งแรกไม่สำเร็จ';
  assert not public.record_item_view_event(-1), 'RPC ยอมรับรหัสสินค้าที่ไม่ถูกต้อง';
  select rank_score into score_with_view from public.home_feed_ranked_v
    where id = equipment_id;
  assert score_with_view > score_without_view, 'ฟีดไม่ได้ใช้ประวัติใหม่จัดอันดับ';

  reset role;
  update public.user_item_views set last_viewed_at = now() - interval '2 minutes'
    where user_id = viewer and item_id = equipment_id;
  set local role authenticated;
  assert public.record_item_view_event(equipment_id), 'เปิดซ้ำแล้วไม่ได้อัปเดตเวลาดูล่าสุด';
  select count(*) into last_view_count from public.user_item_views where item_id = equipment_id
    and last_viewed_at >= now();
  assert last_view_count = 1, 'เปิดซ้ำต้องเหลือหนึ่งแถวพร้อมเวลาดูล่าสุด';

  perform set_config('request.jwt.claim.sub', other_viewer::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', other_viewer, 'role', 'authenticated', 'is_anonymous', false)::text, true);
  assert not exists (select 1 from public.user_item_views where item_id = equipment_id),
    'ผู้ใช้อ่านประวัติของบัญชีอื่นได้';
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', other_viewer, 'role', 'authenticated', 'is_anonymous', true)::text, true);
  assert not public.record_item_view_event(equipment_id), 'บัญชีนิรนามบันทึกประวัติได้';
  reset role;

  update public.user_item_views set last_viewed_at = now() - interval '181 days'
    where user_id = viewer and item_id = equipment_id;
  perform public.purge_old_item_view_events();
  assert not exists (select 1 from public.user_item_views where item_id = equipment_id),
    'งานล้างประวัติไม่ได้ลบแถวที่หมดอายุ';
end
$$;

rollback;
