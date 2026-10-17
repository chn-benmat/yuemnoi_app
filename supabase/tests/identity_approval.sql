-- ใช้ข้อมูลสมมติใน transaction และ rollback ทุกครั้ง เพื่อไม่แก้สถานะผู้ใช้จริง
begin;

do $verify$
declare
 actor uuid := gen_random_uuid();
 applicant uuid := gen_random_uuid();
 outsider uuid := gen_random_uuid();
 request_id uuid := gen_random_uuid();
 self_request uuid := gen_random_uuid();
 duplicate_request uuid := gen_random_uuid();
 scenario jsonb;
 result jsonb;
begin
 insert into auth.users(id, email, raw_user_meta_data, raw_app_meta_data)
 values (actor, actor::text || '@example.invalid', '{}'::jsonb, '{}'::jsonb),
        (applicant, applicant::text || '@example.invalid', '{}'::jsonb, '{}'::jsonb),
        (outsider, outsider::text || '@example.invalid', '{}'::jsonb, '{}'::jsonb);
 insert into ops_private.staff_accounts(user_id) values(actor);
 insert into identity_private.identity_requests(id, user_id, status, consent_version, legal_name, masked_id, citizen_hmac)
 values(request_id, applicant, 'pending', 'identity-v1', 'ทดสอบระบบ', 'test-masked', request_id::text),
       (self_request, actor, 'pending', 'identity-v1', 'ทดสอบระบบ', 'test-masked', self_request::text),
       (duplicate_request, outsider, 'pending', 'identity-v1', 'ทดสอบระบบ', 'test-masked', request_id::text);

 -- เรียกด้วย role เดียวกับ Go Backend เพื่อให้การตรวจสิทธิ์ตรงกับการใช้งานจริง
 perform set_config('role', 'service_role', true);
 for scenario in select value from jsonb_array_elements('[
  {"data":{"decision":"approved"},"error":"manual_review_required"},
  {"data":{"decision":"approved","checked":false},"error":"manual_review_required"},
  {"data":{"decision":"rejected","checked":true},"error":"reason_required"},
  {"data":{"decision":"corrections","checked":true,"reason":"   "},"error":"reason_required"},
  {"data":{"decision":"rejected","checked":true,"reason":"ab"},"error":"reason_required"},
  {"data":{"decision":"approved","checked":true,"reason":"ab"},"error":"reason_required"}
 ]'::jsonb)
 loop
  begin
   perform public.admin_action(actor,'identity-review',request_id::text,scenario->'data');
   raise exception 'expected_error:%', scenario->>'error';
  exception when raise_exception then
   if sqlerrm <> scenario->>'error' then raise; end if;
  end;
 end loop;
 begin
  perform public.admin_action(actor,'hide-item','1','{"enabled":true}'::jsonb);
  raise exception 'expected_reason_required';
 exception when raise_exception then
  if sqlerrm <> 'reason_required' then raise; end if;
 end;
 begin
  perform public.admin_action(outsider,'identity-review',request_id::text,'{"decision":"approved","checked":true}'::jsonb);
  raise exception 'expected_staff_required';
 exception when raise_exception then
  if sqlerrm <> 'staff_required' then raise; end if;
 end;
 begin
  perform public.admin_action(actor,'identity-review',self_request::text,'{"decision":"approved","checked":true}'::jsonb);
  raise exception 'expected_self_review_forbidden';
 exception when raise_exception then
  if sqlerrm <> 'self_review_forbidden' then raise; end if;
 end;

 result := public.admin_action(actor,'identity-review',request_id::text,'{"decision":"approved","checked":true}'::jsonb);
 if result->>'ok' <> 'true' then raise exception 'approval_failed'; end if;
 if not exists(select 1 from identity_private.identity_profiles where user_id=applicant and status='approved' and expires_on is null and not lifetime and reviewed_by=actor) then
  raise exception 'approval_profile_invalid';
 end if;
 if not exists(select 1 from identity_private.identity_requests where id=request_id and status='approved' and reason is null and reviewed_by=actor) then
  raise exception 'approval_request_invalid';
 end if;
 if not exists(select 1 from ops_private.staff_audit where actor_id=actor and target=request_id::text and action='identity-review' and reason is null) then
  raise exception 'approval_audit_missing';
 end if;
 if not app_private.eligible_lessor(applicant) then raise exception 'approved_applicant_not_eligible'; end if;
 begin
  perform public.admin_action(actor,'identity-review',request_id::text,'{"decision":"approved","checked":true}'::jsonb);
  raise exception 'expected_request_not_pending';
 exception when raise_exception then
  if sqlerrm <> 'request_not_pending' then raise; end if;
 end;
 begin
  perform public.admin_action(actor,'identity-review',duplicate_request::text,'{"decision":"approved","checked":true}'::jsonb);
  raise exception 'expected_identity_duplicate';
 exception when raise_exception then
  if sqlerrm <> 'identity_duplicate' then raise; end if;
 end;

 -- ข้อมูลอายุบัตรเดิมไม่มีผลต่อสถานะหรือสิทธิ์หลังเจ้าหน้าที่อนุมัติ
 update identity_private.identity_profiles set expires_on=current_date-1 where user_id=applicant;
 if not app_private.eligible_lessor(applicant) then raise exception 'legacy_card_expiry_blocked_approval'; end if;
 if (public.identity_status(applicant)->>'can_list')::boolean is not true then raise exception 'legacy_card_expiry_blocked_api'; end if;
 for scenario in select value from jsonb_array_elements('[{}, {"lifetime":false}, {"lifetime":false,"expires_on":"2000-01-01"}, {"lifetime":false,"expires_on":"invalid-date"}, {"lifetime":true}]'::jsonb)
 loop
  update identity_private.identity_requests set status='pending', expires_on=current_date-1, lifetime=false where id=request_id;
  perform public.admin_action(actor,'identity-review',request_id::text,'{"decision":"approved","checked":true}'::jsonb || scenario);
  if not exists(select 1 from identity_private.identity_profiles where user_id=applicant and status='approved' and not lifetime and expires_on is null) then
   raise exception 'card_validity_was_not_ignored';
  end if;
  if not app_private.eligible_lessor(applicant) then raise exception 'manual_approval_not_eligible'; end if;
 end loop;
 update identity_private.identity_profiles set status='revoked' where user_id=applicant;
 if app_private.eligible_lessor(applicant) then raise exception 'revoked_profile_eligible'; end if;
 update identity_private.identity_profiles set status='approved' where user_id=applicant;

 -- การระงับบัญชียังคงจำกัดสิทธิ์ตามเดิม
 insert into ops_private.account_controls(user_id,suspended,reason) values(applicant,true,'ทดสอบระงับบัญชี');
 if app_private.eligible_lessor(applicant) then raise exception 'suspended_profile_eligible'; end if;

 for scenario in select value from jsonb_array_elements('["rejected","corrections"]'::jsonb)
 loop
  update identity_private.identity_requests set status='pending' where id=request_id;
  perform public.admin_action(actor,'identity-review',request_id::text,jsonb_build_object('decision',scenario,'checked',true,'reason','ขอให้ตรวจข้อมูลอีกครั้ง'));
  if not exists(select 1 from identity_private.identity_requests where id=request_id and to_jsonb(status)=scenario and reason='ขอให้ตรวจข้อมูลอีกครั้ง') then
   raise exception 'reasoned_review_failed';
  end if;
 end loop;
end
$verify$;

rollback;
select 'identity approval contract checks passed; fixtures rolled back' as result;
