-- JAENS Family OS - Stage 1: family, members, device pairing (QR), My Day.
-- Every family-owned row carries family_id. Row Level Security is on for every
-- table; writes that need several checks go through SECURITY DEFINER functions.
-- No NIK, KK number or home address is ever stored.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------- types
create type public.member_role as enum ('FAMILY_OWNER', 'PARENT_GUARDIAN', 'CHILD');
create type public.theme_mode as enum ('KIDS_BOY', 'KIDS_GIRL', 'TEEN', 'PARENT');
create type public.gender as enum ('BOY', 'GIRL');
create type public.activity_category as enum ('SCHOOL', 'STUDY', 'SPORT', 'FAMILY', 'HEALTH', 'BEDTIME', 'OTHER');
create type public.repeat_type as enum ('ONCE', 'DAILY', 'WEEKDAYS', 'WEEKLY');
create type public.pairing_status as enum ('PAIRED', 'UNPAIRED');

-- ---------------------------------------------------------------- tables
create table public.family (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 60),
  timezone    text not null default 'Asia/Jakarta',
  created_by  uuid not null references auth.users (id),
  created_at  timestamptz not null default now()
);

create table public.family_member (
  id             uuid primary key default gen_random_uuid(),
  family_id      uuid not null references public.family (id) on delete cascade,
  user_id        uuid unique references auth.users (id) on delete set null,
  name           text not null check (char_length(name) between 1 and 40),
  nickname       text check (char_length(nickname) <= 20),
  date_of_birth  date,
  gender         public.gender,
  relationship   text not null default 'Child' check (char_length(relationship) <= 20),
  role           public.member_role not null,
  theme_mode     public.theme_mode not null default 'PARENT',
  avatar_emoji   text not null default '🙂',
  photo_path     text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index on public.family_member (family_id);
-- Exactly one owner per family.
create unique index family_one_owner on public.family_member (family_id) where role = 'FAMILY_OWNER';

create table public.member_permission (
  member_id   uuid not null references public.family_member (id) on delete cascade,
  family_id   uuid not null references public.family (id) on delete cascade,
  capability  text not null check (capability in ('activities.manage', 'announcements.create', 'location.view')),
  primary key (member_id, capability)
);

create table public.device (
  id              uuid primary key default gen_random_uuid(),
  family_id       uuid not null references public.family (id) on delete cascade,
  member_id       uuid not null references public.family_member (id) on delete cascade,
  auth_user_id    uuid references auth.users (id) on delete set null,
  device_name     text not null default 'iPhone',
  platform        text not null default 'ios',
  push_token      text,
  pairing_status  public.pairing_status not null default 'PAIRED',
  paired_at       timestamptz not null default now(),
  unpaired_at     timestamptz,
  last_seen_at    timestamptz
);
create index on public.device (family_id);

-- Only the hash of a pairing code is stored. Codes live 10 minutes and work once.
create table public.pairing_code (
  id          uuid primary key default gen_random_uuid(),
  family_id   uuid not null references public.family (id) on delete cascade,
  member_id   uuid not null references public.family_member (id) on delete cascade,
  code_hash   text not null unique,
  created_by  uuid not null references public.family_member (id),
  expires_at  timestamptz not null,
  used_at     timestamptz,
  created_at  timestamptz not null default now()
);

create table public.activity (
  id               uuid primary key default gen_random_uuid(),
  family_id        uuid not null references public.family (id) on delete cascade,
  member_id        uuid not null references public.family_member (id) on delete cascade,
  title            text not null check (char_length(title) between 1 and 40),
  icon             text not null default '⭐',
  note             text check (char_length(note) <= 200),
  category         public.activity_category not null default 'OTHER',
  start_date       date not null,
  start_time       time not null,
  end_time         time,
  location_name    text check (char_length(location_name) <= 40),
  repeat_type      public.repeat_type not null default 'ONCE',
  repeat_days      smallint[] not null default '{}', -- ISO weekday 1=Mon..7=Sun, for WEEKLY
  reminder_offset  smallint check (reminder_offset in (0, 10, 15, 30, 60)),
  active           boolean not null default true,
  created_by       uuid not null references public.family_member (id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (end_time is null or end_time > start_time),
  check (repeat_type <> 'WEEKLY' or cardinality(repeat_days) > 0),
  check (repeat_days <@ array[1,2,3,4,5,6,7]::smallint[])
);
create index on public.activity (family_id, member_id);

-- Only DONE is stored. Upcoming / Now / Missed are worked out from the clock.
create table public.activity_completion (
  activity_id    uuid not null references public.activity (id) on delete cascade,
  family_id      uuid not null references public.family (id) on delete cascade,
  member_id      uuid not null references public.family_member (id) on delete cascade,
  activity_date  date not null,
  completed_at   timestamptz not null default now(),
  primary key (activity_id, activity_date)
);

create table public.audit_event (
  id               bigint generated always as identity primary key,
  family_id        uuid not null references public.family (id) on delete cascade,
  actor_member_id  uuid references public.family_member (id) on delete set null,
  action           text not null,
  target_id        uuid,
  created_at       timestamptz not null default now()
);
create index on public.audit_event (family_id, created_at desc);

-- ---------------------------------------------------------------- helpers
-- The caller's member row. One signed-in user = one family member.
create or replace function public.my_member_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.family_member where user_id = auth.uid()
$$;

create or replace function public.my_family_id() returns uuid
language sql stable security definer set search_path = public as $$
  select family_id from public.family_member where user_id = auth.uid()
$$;

create or replace function public.my_role() returns public.member_role
language sql stable security definer set search_path = public as $$
  select role from public.family_member where user_id = auth.uid()
$$;

create or replace function public.is_owner() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() = 'FAMILY_OWNER', false)
$$;

create or replace function public.is_parent() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() in ('FAMILY_OWNER', 'PARENT_GUARDIAN'), false)
$$;

create or replace function public.can(p_capability text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or exists (
    select 1 from public.member_permission
    where member_id = public.my_member_id() and capability = p_capability
  )
$$;

create or replace function public.family_today() returns date
language sql stable security definer set search_path = public as $$
  select (now() at time zone coalesce(
    (select timezone from public.family where id = public.my_family_id()), 'Asia/Jakarta'))::date
$$;

create or replace function public.auto_theme(p_role public.member_role, p_dob date, p_gender public.gender)
returns public.theme_mode language sql immutable as $$
  select case
    when p_role <> 'CHILD' then 'PARENT'::public.theme_mode
    when p_dob is not null and extract(year from age(p_dob)) >= 15 then 'TEEN'
    when p_gender = 'BOY' then 'KIDS_BOY'
    else 'KIDS_GIRL'
  end
$$;

create or replace function public.log_event(p_family uuid, p_action text, p_target uuid)
returns void language sql security definer set search_path = public as $$
  insert into public.audit_event (family_id, actor_member_id, action, target_id)
  values (p_family, public.my_member_id(), p_action, p_target)
$$;
revoke execute on function public.log_event(uuid, text, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- RLS
alter table public.family              enable row level security;
alter table public.family_member       enable row level security;
alter table public.member_permission   enable row level security;
alter table public.device              enable row level security;
alter table public.pairing_code        enable row level security;
alter table public.activity            enable row level security;
alter table public.activity_completion enable row level security;
alter table public.audit_event         enable row level security;

-- family
create policy family_read on public.family for select to authenticated
  using (id = public.my_family_id());
create policy family_owner_update on public.family for update to authenticated
  using (id = public.my_family_id() and public.is_owner())
  with check (id = public.my_family_id());

-- members: everyone in the family sees the member list; only the owner changes it.
create policy member_read on public.family_member for select to authenticated
  using (family_id = public.my_family_id());
create policy member_owner_update on public.family_member for update to authenticated
  using (family_id = public.my_family_id() and public.is_owner())
  with check (family_id = public.my_family_id());
create policy member_owner_delete on public.family_member for delete to authenticated
  using (family_id = public.my_family_id() and public.is_owner() and role <> 'FAMILY_OWNER');
-- Inserts go through add_member().

-- permissions
create policy perm_read on public.member_permission for select to authenticated
  using (family_id = public.my_family_id() and (public.is_parent() or member_id = public.my_member_id()));
create policy perm_owner_write on public.member_permission for all to authenticated
  using (family_id = public.my_family_id() and public.is_owner())
  with check (family_id = public.my_family_id() and public.is_owner());

-- devices: parents see all family devices, a child sees their own. Writes via functions.
create policy device_read on public.device for select to authenticated
  using (family_id = public.my_family_id() and (public.is_parent() or member_id = public.my_member_id()));

-- pairing_code: no policies = no direct access. Functions only.

-- activities: parents see the family's, a child sees their own.
create policy activity_read on public.activity for select to authenticated
  using (family_id = public.my_family_id() and (public.is_parent() or member_id = public.my_member_id()));
create policy activity_insert on public.activity for insert to authenticated
  with check (
    family_id = public.my_family_id() and public.can('activities.manage')
    and created_by = public.my_member_id()
    and exists (select 1 from public.family_member m where m.id = member_id and m.family_id = public.my_family_id())
  );
create policy activity_update on public.activity for update to authenticated
  using (family_id = public.my_family_id() and public.can('activities.manage'))
  with check (
    family_id = public.my_family_id()
    and exists (select 1 from public.family_member m where m.id = member_id and m.family_id = public.my_family_id())
  );
create policy activity_delete on public.activity for delete to authenticated
  using (family_id = public.my_family_id() and public.is_owner());

-- completions: a member ticks their own activity, today only. Parents can read.
create policy completion_read on public.activity_completion for select to authenticated
  using (family_id = public.my_family_id() and (public.is_parent() or member_id = public.my_member_id()));
create policy completion_insert on public.activity_completion for insert to authenticated
  with check (
    family_id = public.my_family_id()
    and member_id = public.my_member_id()
    and activity_date = public.family_today()
    and exists (select 1 from public.activity a
                where a.id = activity_id and a.member_id = public.my_member_id() and a.active)
  );
create policy completion_undo on public.activity_completion for delete to authenticated
  using (member_id = public.my_member_id() and activity_date = public.family_today());

-- audit: owner only.
create policy audit_owner_read on public.audit_event for select to authenticated
  using (family_id = public.my_family_id() and public.is_owner());

-- ---------------------------------------------------------------- triggers
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
create trigger member_touch before update on public.family_member
  for each row execute function public.touch_updated_at();
create trigger activity_touch before update on public.activity
  for each row execute function public.touch_updated_at();

-- A member's family, role and login link can't be changed by a plain update.
create or replace function public.guard_member_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if current_setting('jaens.internal', true) = 'on' then return new; end if;
  if new.family_id <> old.family_id or new.user_id is distinct from old.user_id then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  if new.role <> old.role and (old.role = 'FAMILY_OWNER' or new.role = 'FAMILY_OWNER') then
    raise exception 'Not allowed' using errcode = '42501';
  end if;
  if new.role <> old.role then
    perform public.log_event(new.family_id, 'role.changed', new.id);
  else
    perform public.log_event(new.family_id, 'member.edited', new.id);
  end if;
  return new;
end $$;
create trigger member_guard before update on public.family_member
  for each row execute function public.guard_member_update();

create or replace function public.audit_activity_delete() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.log_event(old.family_id, 'activity.deleted', old.id);
  return old;
end $$;
create trigger activity_audit_delete after delete on public.activity
  for each row execute function public.audit_activity_delete();

-- activity.family_id must match the member's family.
create or replace function public.guard_activity() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.family_member where id = new.member_id and family_id = new.family_id) then
    raise exception 'Member is not in this family' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger activity_guard before insert or update on public.activity
  for each row execute function public.guard_activity();

create or replace function public.fill_completion() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select family_id, member_id into new.family_id, new.member_id from public.activity where id = new.activity_id;
  return new;
end $$;
-- (runs before RLS check: family/member always come from the activity itself)
create trigger completion_fill before insert on public.activity_completion
  for each row execute function public.fill_completion();

-- ---------------------------------------------------------------- functions the app calls
-- Parent onboarding: the signed-in user creates the family and becomes its owner.
create or replace function public.create_family(p_family_name text, p_owner_name text, p_relationship text default 'Papa')
returns uuid language plpgsql security definer set search_path = public as $$
declare v_family uuid; v_member uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if public.my_member_id() is not null then raise exception 'You are already in a family' using errcode = '23505'; end if;
  if coalesce((select is_anonymous from auth.users where id = auth.uid()), false) then
    raise exception 'Parents sign in with email to create a family' using errcode = '42501';
  end if;
  insert into public.family (name, created_by) values (trim(p_family_name), auth.uid()) returning id into v_family;
  insert into public.family_member (family_id, user_id, name, relationship, role, theme_mode, avatar_emoji)
  values (v_family, auth.uid(), trim(p_owner_name), coalesce(p_relationship, 'Papa'), 'FAMILY_OWNER', 'PARENT', '👨')
  returning id into v_member;
  insert into public.audit_event (family_id, actor_member_id, action, target_id) values (v_family, v_member, 'family.created', v_family);
  return v_family;
end $$;

-- Owner adds a member (child or second parent). Theme is picked from age and gender.
create or replace function public.add_member(
  p_name text, p_role public.member_role, p_relationship text,
  p_nickname text default null, p_date_of_birth date default null,
  p_gender public.gender default null, p_avatar_emoji text default '🙂')
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_owner() then raise exception 'Only the family owner can add members' using errcode = '42501'; end if;
  if p_role = 'FAMILY_OWNER' then raise exception 'A family has one owner' using errcode = '42501'; end if;
  insert into public.family_member (family_id, name, nickname, date_of_birth, gender, relationship, role, theme_mode, avatar_emoji)
  values (public.my_family_id(), trim(p_name), nullif(trim(p_nickname), ''), p_date_of_birth, p_gender,
          coalesce(nullif(trim(p_relationship), ''), 'Child'), p_role,
          public.auto_theme(p_role, p_date_of_birth, p_gender), coalesce(p_avatar_emoji, '🙂'))
  returning id into v_id;
  if p_role = 'PARENT_GUARDIAN' then
    insert into public.member_permission (member_id, family_id, capability)
    values (v_id, public.my_family_id(), 'activities.manage'), (v_id, public.my_family_id(), 'announcements.create');
  end if;
  perform public.log_event(public.my_family_id(), 'member.created', v_id);
  return v_id;
end $$;

-- Owner makes a one-time code for "Add device" (shown as a QR on the parent phone).
create or replace function public.create_pairing_code(p_member_id uuid)
returns table (code text, expires_at timestamptz)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; -- no 0/O, 1/I/L
  v_code text := '';
  v_bytes bytea := gen_random_bytes(8);
  v_role public.member_role;
  i int;
begin
  if not public.is_owner() then raise exception 'Only the family owner can add devices' using errcode = '42501'; end if;
  select role into v_role from public.family_member where id = p_member_id and family_id = public.my_family_id();
  if v_role is null then raise exception 'Member not found' using errcode = 'P0002'; end if;
  if v_role = 'FAMILY_OWNER' then raise exception 'The owner signs in with email' using errcode = '42501'; end if;
  for i in 0..7 loop
    v_code := v_code || substr(v_alphabet, 1 + (get_byte(v_bytes, i) % length(v_alphabet)), 1);
  end loop;
  -- Old unused codes for this member stop working.
  update public.pairing_code set used_at = now() where member_id = p_member_id and used_at is null;
  insert into public.pairing_code (family_id, member_id, code_hash, created_by, expires_at)
  values (public.my_family_id(), p_member_id, encode(digest(v_code, 'sha256'), 'hex'),
          public.my_member_id(), now() + interval '10 minutes');
  code := v_code; expires_at := now() + interval '10 minutes';
  return next;
end $$;

-- The child's phone (signed in anonymously) scans the QR and joins as that member.
-- The session then stays on the phone: no daily password for kids.
create or replace function public.redeem_pairing_code(p_code text, p_device_name text default 'iPhone')
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_pc public.pairing_code; v_device uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if public.my_member_id() is not null then raise exception 'This phone is already in a family' using errcode = '23505'; end if;
  select * into v_pc from public.pairing_code
   where code_hash = encode(digest(upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g')), 'sha256'), 'hex')
   for update;
  if v_pc.id is null or v_pc.used_at is not null or v_pc.expires_at < now() then
    raise exception 'This code has expired. Ask Papa or Mama for a new one.' using errcode = '22023';
  end if;
  update public.pairing_code set used_at = now() where id = v_pc.id;
  -- A member has one phone at a time: the old one is unpaired.
  update public.device set pairing_status = 'UNPAIRED', unpaired_at = now()
   where member_id = v_pc.member_id and pairing_status = 'PAIRED';
  perform set_config('jaens.internal', 'on', true);
  update public.family_member set user_id = auth.uid() where id = v_pc.member_id;
  perform set_config('jaens.internal', 'off', true);
  insert into public.device (family_id, member_id, auth_user_id, device_name)
  values (v_pc.family_id, v_pc.member_id, auth.uid(), left(coalesce(p_device_name, 'iPhone'), 40))
  returning id into v_device;
  insert into public.audit_event (family_id, actor_member_id, action, target_id)
  values (v_pc.family_id, v_pc.member_id, 'device.paired', v_device);
  return v_pc.member_id;
end $$;

-- Owner unpairs a phone. That phone loses access at once.
create or replace function public.unpair_device(p_device_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_dev public.device;
begin
  if not public.is_owner() then raise exception 'Only the family owner can unpair devices' using errcode = '42501'; end if;
  select * into v_dev from public.device where id = p_device_id and family_id = public.my_family_id();
  if v_dev.id is null then raise exception 'Device not found' using errcode = 'P0002'; end if;
  update public.device set pairing_status = 'UNPAIRED', unpaired_at = now() where id = v_dev.id;
  perform set_config('jaens.internal', 'on', true);
  update public.family_member set user_id = null where id = v_dev.member_id and user_id = v_dev.auth_user_id;
  perform set_config('jaens.internal', 'off', true);
  perform public.log_event(v_dev.family_id, 'device.unpaired', v_dev.id);
end $$;

-- My Day: the member's activities on a day, in time order, with Done.
-- SECURITY INVOKER, so the RLS rules above decide what the caller may see.
create or replace function public.my_day(p_member_id uuid, p_day date default null)
returns table (
  activity_id uuid, title text, icon text, category public.activity_category,
  start_time time, end_time time, location_name text, note text, done boolean)
language sql stable security invoker set search_path = public as $$
  with d as (select coalesce(p_day, public.family_today()) as day)
  select a.id, a.title, a.icon, a.category, a.start_time, a.end_time, a.location_name, a.note,
         exists (select 1 from public.activity_completion c where c.activity_id = a.id and c.activity_date = d.day)
  from public.activity a, d
  where a.member_id = p_member_id and a.active and a.start_date <= d.day
    and case a.repeat_type
          when 'ONCE'     then a.start_date = d.day
          when 'DAILY'    then true
          when 'WEEKDAYS' then extract(isodow from d.day) between 1 and 5
          when 'WEEKLY'   then extract(isodow from d.day)::smallint = any (a.repeat_days)
        end
  order by a.start_time
$$;

-- Who can call what.
revoke all on function public.create_family(text, text, text) from public, anon;
revoke all on function public.add_member(text, public.member_role, text, text, date, public.gender, text) from public, anon;
revoke all on function public.create_pairing_code(uuid) from public, anon;
revoke all on function public.redeem_pairing_code(text, text) from public, anon;
revoke all on function public.unpair_device(uuid) from public, anon;
revoke all on function public.my_day(uuid, date) from public, anon;
grant execute on function public.create_family(text, text, text) to authenticated;
grant execute on function public.add_member(text, public.member_role, text, text, date, public.gender, text) to authenticated;
grant execute on function public.create_pairing_code(uuid) to authenticated;
grant execute on function public.redeem_pairing_code(text, text) to authenticated;
grant execute on function public.unpair_device(uuid) to authenticated;
grant execute on function public.my_day(uuid, date) to authenticated;
