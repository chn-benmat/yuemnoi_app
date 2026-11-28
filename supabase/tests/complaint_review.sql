begin;

do $test$
declare
  staff_id uuid := gen_random_uuid();
  owner_id uuid := gen_random_uuid();
  reporter uuid := gen_random_uuid();
  listing bigint;
  other_listing bigint;
  previous_booking bigint;
  first_case uuid := gen_random_uuid();
  second_case uuid := gen_random_uuid();
  third_case uuid := gen_random_uuid();
  duplicate_case uuid := gen_random_uuid();
  dismissed_case uuid := gen_random_uuid();
  other_case uuid := gen_random_uuid();
  first_incident uuid;
  result jsonb;
  verified jsonb := '{"status":"resolved","outcome":"confirmed","reason":"แก้ราคาในประกาศ"}';
begin
  insert into auth.users(id, email) select id, id || '@example.invalid' from unnest(array[staff_id, owner_id, reporter]) id;
  update profiles.profile_tb set phone = '+66812345678' where user_id = owner_id;
  update profiles.profile_tb set phone = '+66823456789' where user_id = reporter;
  insert into identity_private.identity_profiles(user_id, status, legal_name, masked_id, citizen_hmac, is_minor)
  values
    (owner_id, 'approved', 'ผู้ใช้ทดสอบ', '*********1234', md5(owner_id::text) || md5(reporter::text), false),
    (reporter, 'approved', 'ผู้เช่าทดสอบ', '*********4321', md5(reporter::text) || md5(owner_id::text), false);
  insert into ops_private.staff_accounts(user_id) values (staff_id);
  insert into public.item_tb(user_id, item_name, description, price, status, type,
    pickup_location, pickup_address, pickup_latitude, pickup_longitude)
  values (owner_id, 'โต๊ะทดสอบ', 'ทดสอบระบบ', 100, 'available', 'daily', 'จุดรับ', 'ที่อยู่ทดสอบ', 13.75, 100.50)
  returning id into listing;
  insert into public.item_tb(user_id, item_name, description, price, status, type,
    pickup_location, pickup_address, pickup_latitude, pickup_longitude)
  values (owner_id, 'เก้าอี้ทดสอบ', 'ทดสอบระบบ', 100, 'available', 'daily', 'จุดรับ', 'ที่อยู่ทดสอบ', 13.75, 100.50)
  returning id into other_listing;
  select id into previous_booking from public.create_rental_request(
    reporter, listing, now() + interval '1 day', now() + interval '2 days', 'daily', 'จุดรับ');
  insert into ops_private.complaints(id, reporter_id, item_id, description, status) values
    (first_case, reporter, listing, 'ราคาไม่ตรงตามประกาศ', 'in_progress'),
    (second_case, reporter, listing, 'รายละเอียดอุปกรณ์ผิด', 'open'),
    (third_case, reporter, listing, 'อุปกรณ์ไม่ครบชุด', 'open'),
    (duplicate_case, reporter, listing, 'พบราคาไม่ตรงเช่นกัน', 'open'),
    (dismissed_case, reporter, listing, 'ราคาตรงตามหลักฐาน', 'open'),
    (other_case, reporter, other_listing, 'แจ้งเกี่ยวกับอีกประกาศ', 'open');

  begin
    perform public.admin_review_complaint(reporter, first_case, verified);
    raise exception 'non-staff review unexpectedly succeeded';
  exception when raise_exception then
    if sqlerrm <> 'staff_required' then raise; end if;
  end;
  begin
    perform public.admin_action(staff_id, 'complaint', first_case::text,
      '{"status":"resolved","reason":"old client bypass"}');
    raise exception 'legacy complaint endpoint bypassed required outcome';
  exception when raise_exception then
    if sqlerrm <> 'invalid_complaint_outcome' then raise; end if;
  end;

  perform public.admin_review_complaint(staff_id, dismissed_case, '{"status":"in_progress"}');
  if not exists (
    select 1 from ops_private.complaints where id = dismissed_case
      and status = 'in_progress' and assigned_to = staff_id and resolution is null
  ) then
    raise exception 'claim did not assign the case';
  end if;
  perform public.admin_review_complaint(staff_id, dismissed_case,
    '{"status":"resolved","outcome":"dismissed","reason":"ราคาตรงตามหลักฐาน"}');
  result := public.admin_complaint_context(staff_id, first_case);
  if result->>'strike_count' is distinct from '0' then
    raise exception 'dismissed case added a strike: %', result;
  end if;

  result := public.admin_review_complaint(staff_id, first_case, verified);
  if result->>'strike_count' is distinct from '1' or result->>'item_hidden' is distinct from 'false' then
    raise exception 'first verified case has wrong result: %', result;
  end if;
  perform public.admin_review_complaint(staff_id, first_case, verified);
  result := public.admin_complaint_context(staff_id, duplicate_case);
  if result->>'strike_count' is distinct from '1' or jsonb_array_length(result->'incidents') <> 1 then
    raise exception 'retry counted as another incident: %', result;
  end if;
  first_incident := (result->'incidents'->0->>'id')::uuid;
  begin
    perform public.admin_review_complaint(staff_id, other_case,
      jsonb_build_object('status', 'resolved', 'outcome', 'duplicate', 'incident_id', first_incident));
    raise exception 'linked an incident for a different listing';
  exception when raise_exception then
    if sqlerrm <> 'invalid_complaint_incident' then raise; end if;
  end;
  perform public.admin_review_complaint(staff_id, duplicate_case,
    jsonb_build_object('status', 'resolved', 'outcome', 'duplicate', 'incident_id', first_incident));
  if not exists (
    select 1 from ops_private.complaints where id = duplicate_case
      and status = 'resolved' and review_outcome = 'duplicate' and incident_id = first_incident
  ) then
    raise exception 'duplicate case did not link to the original incident';
  end if;

  result := public.admin_review_complaint(staff_id, second_case, verified);
  if result->>'strike_count' is distinct from '2' or result->>'item_hidden' is distinct from 'false' then
    raise exception 'second confirmed incident hid the listing early: %', result;
  end if;
  result := public.admin_review_complaint(staff_id, third_case, verified);
  if result->>'strike_count' is distinct from '3' or result->>'item_hidden' is distinct from 'true' then
    raise exception 'third confirmed incident did not hide the listing: %', result;
  end if;

  if (select count(*) from notifications.notification_tb where user_id = owner_id and type = 'complaint_listing_warning') <> 2
    or (select count(*) from notifications.notification_tb where user_id = owner_id and type = 'complaint_listing_removed') <> 1
    or exists (select 1 from notifications.notification_tb where user_id = owner_id and type = 'item_hidden')
    or not exists (select 1 from notifications.notification_tb where user_id = owner_id
      and type = 'complaint_listing_warning' and body like '%แก้ราคาในประกาศ%') then
    raise exception 'wrong complaint notices for listing owner';
  end if;
  if exists (select 1 from notifications.notification_tb where user_id = owner_id
      and type in ('complaint_listing_warning','complaint_listing_removed') and data::text like '%' || reporter::text || '%') then
    raise exception 'complaint notice exposed reporter identity';
  end if;
  if not exists (select 1 from public.item_tb where id = listing and moderation_hidden)
    or exists (select 1 from public.item_tb where id = other_listing and moderation_hidden) then
    raise exception 'removal affected the wrong listing';
  end if;
  if not exists (select 1 from public.booking_tb where id = previous_booking and item_id = listing) then
    raise exception 'removal erased a previous booking';
  end if;
  begin
    perform public.create_rental_request(
      reporter, listing, now() + interval '3 days', now() + interval '4 days', 'daily', 'จุดรับ');
    raise exception 'a new booking was created for a removed listing';
  exception when raise_exception then
    if sqlerrm <> 'item_unavailable' then raise; end if;
  end;
  begin
    update public.item_tb set moderation_hidden = false where id = listing;
    raise exception 'restored a listing removed by the complaint policy';
  exception when raise_exception then
    if sqlerrm <> 'complaint_item_removed' then raise; end if;
  end;

  delete from ops_private.complaints where id = first_case;
  result := public.admin_complaint_context(staff_id, third_case);
  if result->>'strike_count' is distinct from '3' then
    raise exception 'deleting a report removed a verified incident: %', result;
  end if;
end
$test$;

rollback;
