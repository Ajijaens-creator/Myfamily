-- Stage 1 security tests. Run after the migration (see .github/workflows/ios.yml).
\set ON_ERROR_STOP on
grant select, insert, update, delete on all tables in schema public to authenticated;

insert into auth.users values
 ('00000000-0000-0000-0000-00000000000a', false),  -- Ajik (owner)
 ('00000000-0000-0000-0000-00000000000b', true),   -- Ibuk phone
 ('00000000-0000-0000-0000-00000000000c', true),   -- Raiya phone
 ('00000000-0000-0000-0000-00000000000d', true),   -- Rada phone
 ('00000000-0000-0000-0000-00000000000e', false);  -- stranger with own family

create or replace function pg_temp.as_user(u text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', u, false); $$;

set role authenticated;
-- Owner creates family and members
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select create_family('Jaens Family', 'Ajik', 'Papa') is not null as family_created;
select add_member('Ibuk', 'PARENT_GUARDIAN', 'Mama') as ibuk \gset
select add_member('Raiya', 'CHILD', 'Daughter', 'Raiya', (current_date - interval '8 years')::date, 'GIRL', '🌸') as raiya \gset
select add_member('Rada', 'CHILD', 'Daughter', 'Rada', (current_date - interval '14 years')::date, 'GIRL', '🦋') as rada \gset
select add_member('Radja', 'CHILD', 'Son', 'Radja', (current_date - interval '16 years')::date, 'BOY', '⚽') as radja \gset
do $$ begin
  assert (select theme_mode from family_member where name='Raiya') = 'KIDS_GIRL', 'Raiya theme';
  assert (select theme_mode from family_member where name='Radja') = 'TEEN', 'Radja theme';
end $$;

-- Pair Raiya's phone
select code as raiya_code from create_pairing_code(:'raiya') \gset
select code as rada_code from create_pairing_code(:'rada') \gset
select code as ibuk_code from create_pairing_code(:'ibuk') \gset

insert into activity (family_id, member_id, title, icon, category, start_date, start_time, end_time, repeat_type, created_by)
select my_family_id(), :'raiya', 'School', '🏫', 'SCHOOL', current_date - 3, '07:00', '12:00', 'DAILY', my_member_id();
insert into activity (family_id, member_id, title, icon, category, start_date, start_time, repeat_type, created_by)
select my_family_id(), :'rada', 'English', '📘', 'STUDY', current_date, '15:30', 'ONCE', my_member_id();

select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select redeem_pairing_code(:'raiya_code', 'Raiya iPhone') = :'raiya'::uuid as raiya_joined;
-- a code works once (another phone tries the same code)
select set_config('my.code', :'raiya_code', false);
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
do $$ begin
  begin
    perform redeem_pairing_code(current_setting('my.code'), 'x');
    raise exception 'reuse should fail';
  exception when invalid_parameter_value then null; end;
end $$;

select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select redeem_pairing_code(lower(:'rada_code'), 'Rada iPhone') = :'rada'::uuid as rada_joined_lowercase_ok;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select redeem_pairing_code(:'ibuk_code') = :'ibuk'::uuid as ibuk_joined;

-- Raiya sees only her own activity; can tick today; can't tick for Rada; can't create activities
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
do $$ begin
  assert (select count(*) from activity) = 1, 'child sees only own activities';
  assert (select count(*) from family_member) = 5, 'child sees family list';
  assert (select count(*) from device) = 1, 'child sees own device only';
  assert (select count(*) from audit_event) = 0, 'child cannot read audit';
end $$;
select count(*) = 1 as raiya_my_day from my_day(my_member_id());
insert into activity_completion (activity_id, activity_date)
  select id, family_today() from activity;
select bool_and(done) as raiya_done from my_day(my_member_id());
do $$ begin
  begin
    insert into activity (family_id, member_id, title, start_date, start_time, created_by)
    values (my_family_id(), my_member_id(), 'Games', current_date, '20:00', my_member_id());
    raise exception 'child insert should fail';
  exception when insufficient_privilege then null; end;
  begin
    update family_member set role = 'FAMILY_OWNER' where id = my_member_id();
    if found then raise exception 'child role change should fail'; end if;
  end;
  begin
    perform create_pairing_code(my_member_id());
    raise exception 'child pairing should fail';
  exception when insufficient_privilege then null; end;
  begin
    insert into activity_completion (activity_id, activity_date)
      select id, family_today() - 1 from activity;
    raise exception 'past tick should fail';
  exception when insufficient_privilege then null; end;
end $$;
do $$ begin
  assert (select count(*) from my_day((select id from family_member where name='Rada'))) = 0, 'cannot read sibling day';
end $$;

-- Ibuk (parent with activities.manage) sees all and can add, but cannot delete
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
do $$ begin
  assert (select count(*) from activity) = 2, 'parent sees all';
  insert into activity (family_id, member_id, title, start_date, start_time, created_by)
  values (my_family_id(), (select id from family_member where name='Radja'), 'Futsal', current_date, '16:00', my_member_id());
  delete from activity where title = 'Futsal';
  assert found = false, 'parent guardian cannot delete';
end $$;

-- Stranger in another family sees nothing of the Jaens family
select set_config('my.raiya', :'raiya', false);
select pg_temp.as_user('00000000-0000-0000-0000-00000000000e');
select create_family('Other', 'Budi') is not null as other_family;
do $$ begin
  assert (select count(*) from family_member) = 1, 'stranger sees only own family';
  assert (select count(*) from activity) = 0, 'stranger sees no activities';
  begin
    insert into activity (family_id, member_id, title, start_date, start_time, created_by)
    values (my_family_id(), current_setting('my.raiya')::uuid, 'x', current_date, '10:00', my_member_id());
    raise exception 'cross-family insert should fail';
  exception when insufficient_privilege then null; end;
end $$;

-- Owner unpairs Raiya: her phone loses access
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select unpair_device((select id from device where device_name = 'Raiya iPhone'));
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
do $$ begin
  assert my_member_id() is null, 'unpaired phone has no member';
  assert (select count(*) from activity) = 0, 'unpaired phone sees nothing';
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  assert (select count(*) from audit_event where action in ('device.paired','device.unpaired','member.created')) = 8, 'audit trail';
end $$;
select 'ALL STAGE 1 TESTS PASSED' as result;
