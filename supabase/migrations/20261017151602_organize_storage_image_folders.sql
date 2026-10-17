-- รูปแชตใหม่อยู่ในห้องแชต โดยตรวจสมาชิกห้องแทนไอดีผู้ส่งที่โฟลเดอร์แรก
alter policy chat_bk_insert_policy on storage.objects
with check (
  bucket_id = 'chat_bk'
  and array_length(storage.foldername(name), 1) = 1
  and exists (
    select 1 from public.conversation_tb c
    where c.id::text = (storage.foldername(name))[1]
      and (c.renter_id = (select auth.uid()) or c.owner_id = (select auth.uid()))
  )
);

-- ยังอ่านรูปเดิมที่เป็นผู้ส่ง/ห้องแชต/ชื่อไฟล์ได้ระหว่างเปลี่ยนเวอร์ชันแอป
alter policy chat_bk_select_policy on storage.objects
using (
  bucket_id = 'chat_bk'
  and exists (
    select 1 from public.conversation_tb c
    where c.id::text = case array_length(storage.foldername(name), 1)
      when 1 then (storage.foldername(name))[1]
      when 2 then (storage.foldername(name))[2]
    end
      and (c.renter_id = (select auth.uid()) or c.owner_id = (select auth.uid()))
  )
);

-- ใช้เจ้าของ object ตรวจผู้ส่งสำหรับ path ใหม่ และรองรับการลบรูปเดิมด้วย
alter policy chat_bk_delete_policy on storage.objects
using (
  bucket_id = 'chat_bk'
  and (
    (array_length(storage.foldername(name), 1) = 2
      and (storage.foldername(name))[1] = (select auth.uid())::text)
    or (
      array_length(storage.foldername(name), 1) = 1
      and owner_id = (select auth.uid())::text
      and exists (
        select 1 from public.conversation_tb c
        where c.id::text = (storage.foldername(name))[1]
          and (c.renter_id = (select auth.uid()) or c.owner_id = (select auth.uid()))
      )
    )
  )
);

-- ผู้เช่าแนบภาพคืนสินค้าในโฟลเดอร์เจ้าของสินค้าได้เฉพาะรายการเช่าของตน
create policy item_bk_return_insert_policy on storage.objects
for insert to authenticated
with check (
  bucket_id = 'item_bk'
  and array_length(storage.foldername(name), 1) = 2
  and split_part(storage.filename(name), '_', 1) = 'return'
  and exists (
    select 1 from public.booking_tb b
    join public.item_tb i on i.id = b.item_id
    where b.user_id = (select auth.uid())
      and i.user_id::text = (storage.foldername(name))[1]
      and i.id::text = (storage.foldername(name))[2]
      and b.id::text = split_part(storage.filename(name), '_', 2)
  )
);
