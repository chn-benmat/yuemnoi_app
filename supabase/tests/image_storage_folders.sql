-- ทดสอบสิทธิ์ด้วยข้อมูลสมมติใน transaction และไม่ย้ายไฟล์ของผู้ใช้จริง
begin;
-- อนุญาตคำสั่งลบ metadata สมมติเฉพาะ transaction นี้ เพื่อทดสอบ DELETE RLS
set local storage.allow_delete_query = 'true';

do $verify$
declare
  owner_user uuid := gen_random_uuid();
  renter_user uuid := gen_random_uuid();
  outsider_user uuid := gen_random_uuid();
  room_id uuid := gen_random_uuid();
  item_id bigint := -(1000000000000 + floor(random() * 1000000000000)::bigint);
  booking_id bigint := item_id;
  chat_path text := room_id::text || '/image.jpg';
  legacy_path text := renter_user::text || '/' || room_id::text || '/legacy.jpg';
  return_path text;
  changed integer;
begin
  insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data)
  values (owner_user,owner_user::text || '@example.invalid','{}','{}'),
         (renter_user,renter_user::text || '@example.invalid','{}','{}'),
         (outsider_user,outsider_user::text || '@example.invalid','{}','{}');
  insert into identity_private.identity_profiles(user_id,status,legal_name,masked_id,citizen_hmac,is_minor)
  values(owner_user,'approved','Storage policy test','test-masked',owner_user::text,false);
  insert into public.item_tb(id,user_id,item_name,description) overriding system value
  values(item_id,owner_user,'Storage policy test','Test fixture');
  insert into public.booking_tb(id,user_id,item_id) overriding system value
  values(booking_id,renter_user,item_id);
  insert into public.conversation_tb(id,renter_id,owner_id) values(room_id,renter_user,owner_user);
  insert into storage.objects(bucket_id,name,owner_id) values('chat_bk',legacy_path,renter_user::text);
  return_path := owner_user::text || '/' || item_id::text || '/return_' || booking_id::text || '_angle_1.jpg';

  perform set_config('request.jwt.claims',jsonb_build_object('sub',renter_user,'role','authenticated')::text,true);
  perform set_config('role','authenticated',true);
  insert into storage.objects(bucket_id,name,owner_id) values('chat_bk',chat_path,renter_user::text);
  insert into storage.objects(bucket_id,name,owner_id) values('item_bk',return_path,renter_user::text);
  if (select count(*) from storage.objects where bucket_id='chat_bk' and name in (chat_path,legacy_path)) <> 2 then
    raise exception 'sender cannot read new and legacy chat paths';
  end if;
  begin
    insert into storage.objects(bucket_id,name) values('chat_bk','invalid-room/image.jpg');
    raise exception 'invalid chat folder accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into storage.objects(bucket_id,name)
    values('item_bk',owner_user::text || '/' || item_id::text || '/listing.jpg');
    raise exception 'renter uploaded a listing image under another owner';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into storage.objects(bucket_id,name)
    values('item_bk',owner_user::text || '/' || (item_id-1)::text || '/return_' || booking_id::text || '_wrong-item.jpg');
    raise exception 'return image accepted under the wrong item';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_user,'role','authenticated')::text,true);
  if (select count(*) from storage.objects where bucket_id='chat_bk' and name in (chat_path,legacy_path)) <> 2 then
    raise exception 'recipient cannot read new and legacy chat paths';
  end if;
  delete from storage.objects where bucket_id='chat_bk' and name=chat_path;
  get diagnostics changed = row_count;
  if changed <> 0 then raise exception 'recipient deleted another sender image'; end if;
  insert into storage.objects(bucket_id,name,owner_id)
  values('chat_bk',room_id::text || '/owner-image.jpg',owner_user::text);
  insert into storage.objects(bucket_id,name)
  values('item_bk',owner_user::text || '/' || item_id::text || '/listing.jpg');

  perform set_config('request.jwt.claims',jsonb_build_object('sub',outsider_user,'role','authenticated')::text,true);
  if exists(select 1 from storage.objects where bucket_id='chat_bk' and name in (chat_path,legacy_path)) then
    raise exception 'outsider can read chat images';
  end if;
  begin
    insert into storage.objects(bucket_id,name) values('chat_bk',room_id::text || '/outsider.jpg');
    raise exception 'outsider can upload to chat';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into storage.objects(bucket_id,name)
    values('item_bk',owner_user::text || '/' || item_id::text || '/return_' || booking_id::text || '_outsider.jpg');
    raise exception 'outsider can upload to another booking';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',renter_user,'role','authenticated')::text,true);
  delete from storage.objects where bucket_id='chat_bk' and name in (chat_path,legacy_path);
  get diagnostics changed = row_count;
  if changed <> 2 then raise exception 'sender cannot delete new and legacy chat images'; end if;
  perform set_config('role','postgres',true);
end;
$verify$;

rollback;
select 'image storage policy assertions passed; fixtures rolled back' as result;
