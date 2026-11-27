begin;

do $$
declare
    email_user uuid := gen_random_uuid();
    google_user uuid := gen_random_uuid();
    second_suffix_owner uuid := gen_random_uuid();
    alias_user uuid := gen_random_uuid();
    fallback_user uuid := gen_random_uuid();
    handle text := 'username_test_' || left(replace(gen_random_uuid()::text, '-', ''), 12);
begin
    insert into auth.users (id, email, raw_user_meta_data)
    values (email_user, handle || '@example.invalid', '{"display_name":"Email signup"}');

    assert exists (
        select 1 from profiles.profile_tb
        where user_id = email_user and username = handle
          and display_name = 'Email signup' and username_changed_at is null
    ), 'email signup must use the part before @ without starting the cooldown';

    insert into auth.users (id, email)
    values (second_suffix_owner, handle || '_2@example.invalid');

    insert into auth.users (id, email, raw_user_meta_data)
    values (google_user, upper(handle) || '@example.org', '{"full_name":"Google signup"}');

    assert exists (
        select 1 from profiles.profile_tb
        where user_id = google_user and username = upper(handle) || '_3'
          and display_name = 'Google signup' and username_changed_at is null
    ), 'case-insensitive collisions must skip suffixes that are already taken';

    insert into auth.users (id, email)
    values (alias_user, handle || '.first+tag@example.invalid');

    assert exists (
        select 1 from profiles.profile_tb
        where user_id = alias_user and username = handle || '.first_tag'
    ), 'the initial username must keep valid characters and replace unsupported ones';

    insert into auth.users (id) values (fallback_user);

    assert exists (
        select 1 from profiles.profile_tb
        where user_id = fallback_user and username ~ '^user_[0-9a-f]{32}$'
    ), 'users without an email must receive a valid default username';
end;
$$;

rollback;
