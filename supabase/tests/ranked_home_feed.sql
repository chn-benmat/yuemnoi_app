begin;

do $test$
declare
  guest_result jsonb;
  next_result jsonb;
  personalized jsonb;
  viewer uuid := gen_random_uuid();
  owner_near uuid := gen_random_uuid();
  owner_far uuid := gen_random_uuid();
  near_id bigint;
  far_id bigint;
  hidden_id bigint;
  location_lat constant double precision := 13.75;
  location_lng constant double precision := 100.5;
begin
  assert not has_function_privilege(
    'anon','public.get_home_feed_v2(uuid,double precision,double precision,text[],text,integer)','execute'
  ), 'ผู้เยี่ยมชมเรียกฟังก์ชันด้วยตัวตนบัญชีอื่นได้';
  assert not has_function_privilege(
    'authenticated','public.get_home_feed_v2(uuid,double precision,double precision,text[],text,integer)','execute'
  ), 'แอปเรียกฟังก์ชันด้วยตัวตนบัญชีอื่นได้';

  insert into auth.users(id,email)
  select u, u::text||'@example.invalid' from unnest(array[viewer,owner_near,owner_far]) u;
  insert into public.item_tb(user_id,item_name,description,price,type,category,status,pickup_latitude,pickup_longitude)
  values (owner_near,'กล้องใกล้','ทดสอบ',500,'รายวัน','กล้อง','available',location_lat,location_lng)
  returning id into near_id;
  insert into public.item_tb(user_id,item_name,description,price,type,category,status,pickup_latitude,pickup_longitude)
  values (owner_far,'เต็นท์ไกล','ทดสอบ',500,'รายวัน','แคมป์ปิง','available',0,0)
  returning id into far_id;
  insert into public.item_tb(user_id,item_name,description,price,type,category,status,pickup_latitude,pickup_longitude,owner_hidden)
  values (owner_near,'ซ่อน','ทดสอบ',500,'รายวัน','กล้อง','available',location_lat,location_lng,true)
  returning id into hidden_id;

  insert into public.user_item_views(user_id,item_id,last_viewed_at)
  values (viewer,far_id,statement_timestamp()-interval '1 hour');

  guest_result := public.get_home_feed_v2(null,location_lat,location_lng,'{camera}',null,1);
  assert jsonb_array_length(guest_result->'items') = 1, 'จำนวนสินค้าต่อหน้าไม่ตรง';
  assert (guest_result->'items'->0->>'id')::bigint = near_id, 'สินค้าที่ใกล้และตรงความสนใจควรขึ้นก่อน';
  assert guest_result->>'next_cursor' is not null, 'ไม่มี cursor สำหรับหน้าถัดไป';
  next_result := public.get_home_feed_v2(null,location_lat,location_lng,'{camera}',guest_result->>'next_cursor',48);
  assert exists (select 1 from jsonb_array_elements(next_result->'items') x where (x->>'id')::bigint = far_id);
  assert not exists (select 1 from jsonb_array_elements(next_result->'items') x where (x->>'id')::bigint in (near_id,hidden_id)),
    'หน้าถัดไปซ้ำหรือมีรายการที่ซ่อน';
  personalized := public.get_home_feed_v2(viewer,null,null,'{}',null,1);
  assert (personalized->'items'->0->>'id')::bigint = far_id, 'ประวัติการดูล่าสุดไม่ได้เปลี่ยนลำดับ';

  update public.user_item_views set last_viewed_at = statement_timestamp()
    where user_id = viewer and item_id = far_id;
  begin
    perform public.get_home_feed_v2(viewer,null,null,'{}',personalized->>'next_cursor',1);
    raise exception 'หน้าถัดไปใช้ประวัติที่เปลี่ยนจากหน้าแรก';
  exception when invalid_parameter_value then null;
  end;

  begin
    perform public.get_home_feed_v2(null,91,100,'{}',null,1);
    raise exception 'พิกัดเกินขอบเขตได้รับการยอมรับ';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.get_home_feed_v2(null,null,null,'{}','bad cursor',1);
    raise exception 'cursor ไม่ถูกต้องได้รับการยอมรับ';
  exception when invalid_parameter_value then null;
  end;
end;
$test$;

rollback;
