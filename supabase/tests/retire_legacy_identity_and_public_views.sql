begin;

do $test$
declare
  reviewer uuid := gen_random_uuid();
  customer uuid;
  v_request_id uuid;
  identity_data jsonb;
  evidence jsonb;
  identity_result jsonb;
  legacy_payload boolean;
begin
  assert not exists (
    select from pg_attribute
    where attrelid in ('identity_private.identity_requests'::regclass, 'identity_private.identity_profiles'::regclass)
      and not attisdropped and attname in ('expires_on', 'lifetime')
  ), 'Retired card expiry columns are still present';

  assert not exists (
    select from pg_attribute
    where attrelid in ('app_private.public_profile_source_v'::regclass, 'profiles.public_profile_v'::regclass)
      and not attisdropped and attname in ('email', 'phone')
  ), 'Public profile views still expose contact columns';
  assert (select relowner = 'public_profile_reader'::regrole
                 and reloptions @> array['security_invoker=false','security_barrier=true']
          from pg_class where oid = 'app_private.public_profile_source_v'::regclass);
  assert (select relowner = 'postgres'::regrole
                 and reloptions @> array['security_invoker=true','security_barrier=true']
          from pg_class where oid = 'profiles.public_profile_v'::regclass);
  assert not has_schema_privilege('public_profile_reader', 'app_private', 'CREATE');
  assert not exists (
    select from (values ('anon'), ('authenticated'), ('service_role')) roles(role_name)
    cross join (values ('app_private.public_profile_source_v'), ('profiles.public_profile_v')) views(view_name)
    where not has_table_privilege(role_name, view_name, 'SELECT')
       or has_table_privilege(role_name, view_name, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
  ), 'Public profile read grants changed';

  assert to_regclass('public.home_feed_ranked_with_user_location_v') is null;
  assert to_regclass('public.home_feed_ranked_v') is not null;
  assert to_regprocedure('public.get_home_feed_v2(uuid,double precision,double precision,text[],text,integer)') is not null;

  assert has_function_privilege('service_role', 'public.identity_submit(uuid,uuid,jsonb,jsonb)', 'EXECUTE');
  assert not has_function_privilege('anon', 'public.identity_submit(uuid,uuid,jsonb,jsonb)', 'EXECUTE');
  assert not has_function_privilege('authenticated', 'public.identity_submit(uuid,uuid,jsonb,jsonb)', 'EXECUTE');

  insert into auth.users(id, email) values (reviewer, reviewer::text || '@example.invalid');
  insert into ops_private.staff_accounts(user_id) values (reviewer);

  foreach legacy_payload in array array[false, true] loop
    customer := gen_random_uuid();
    insert into auth.users(id, email) values (customer, customer::text || '@example.invalid');
    v_request_id := (public.identity_begin(customer, false, 'identity-v1')->>'id')::uuid;
    evidence := jsonb_build_array(
      jsonb_build_object('kind', 'card', 'object_path', customer::text || '/card.jpg'),
      jsonb_build_object('kind', 'selfie', 'object_path', customer::text || '/selfie.jpg')
    );
    perform public.identity_reserve_evidence(customer, v_request_id, evidence);
    identity_data := jsonb_build_object(
      'legal_name', 'ผู้ใช้ทดสอบ', 'masked_id', '*********1234',
      'citizen_hmac', md5(customer::text) || md5(customer::text),
      'is_minor', false, 'raw_encrypted', 'test-encrypted-data',
      'analysis', jsonb_build_object('review_mode', 'manual'), 'consent_version', 'identity-v2'
    );
    if legacy_payload then
      -- ค่าเดิมที่แปลเป็นวันที่หรือ boolean ไม่ได้ต้องถูกข้าม
      identity_data := identity_data || '{"expires_on":"invalid date","lifetime":"invalid boolean"}'::jsonb;
    end if;

    set local role service_role;
    identity_result := public.identity_submit(customer, v_request_id, identity_data, evidence);
    assert identity_result->>'status' = 'pending';
    perform ops_private.admin_action(reviewer, 'identity-review', v_request_id::text, '{"decision":"approved","checked":true}');
    identity_result := public.identity_status(customer);
    reset role;

    assert identity_result#>>'{profile,status}' = 'approved';
    assert identity_result#>>'{request,status}' = 'approved';
    assert not (identity_result->'profile' ?| array['expires_on','lifetime']);
    assert not (identity_result->'request' ?| array['expires_on','lifetime']);
    assert exists (select from identity_private.identity_profiles where user_id = customer and source_request_id = v_request_id);
    assert exists (select from identity_private.identity_evidence e where e.request_id = v_request_id and kind = 'card' and delete_at = 'infinity');
    assert exists (select from identity_private.identity_evidence e where e.request_id = v_request_id and kind = 'selfie' and delete_at = now() + interval '7 days');
    assert exists (select from ops_private.staff_audit where actor_id = reviewer and action = 'identity-review' and target = v_request_id::text);
  end loop;
end
$test$;

rollback;
