begin;

do $$
declare
    first_profile bigint;
    second_profile bigint;
    initial_username text;
    change_time timestamptz;
    test_username text := 'test_' || replace(gen_random_uuid()::text, '-', '');
begin
    insert into profiles.profile_tb default values
        returning id, username into first_profile, initial_username;
    insert into profiles.profile_tb default values returning id into second_profile;

    assert initial_username ~ '^[A-Za-z0-9._]+$', 'expected a valid default username';

    begin
        update profiles.profile_tb set username = '' where id = first_profile;
        raise exception 'accepted an empty username';
    exception when check_violation then null;
    end;

    begin
        update profiles.profile_tb set username = 'invalid-name' where id = first_profile;
        raise exception 'accepted an unsupported character';
    exception when check_violation then null;
    end;

    update profiles.profile_tb set username = test_username || '.1' where id = first_profile
        returning username_changed_at into change_time;
    assert change_time is not null, 'expected a timestamp for the first change';

    begin
        update profiles.profile_tb set username = upper(test_username) || '.1' where id = second_profile;
        raise exception 'accepted a duplicate username with different capitalization';
    exception when unique_violation then null;
    end;

    update profiles.profile_tb
       set bio = 'updated', username = test_username || '.1', username_changed_at = null
     where id = first_profile;
    assert (
        select username_changed_at = change_time and bio = 'updated'
        from profiles.profile_tb where id = first_profile
    ), 'saving other fields must preserve the change timestamp';

    begin
        update profiles.profile_tb set username = test_username || '.2' where id = first_profile;
        raise exception 'accepted a second change within 30 days';
    exception when raise_exception then
        if sqlerrm <> 'username_change_cooldown' then
            raise;
        end if;
    end;
end;
$$;

rollback;
