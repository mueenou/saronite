-- Saronite: one shared guild workspace per Supabase project.
-- Apply with `supabase db push` or paste this migration into Supabase SQL Editor.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 60),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    left(coalesce(
      nullif(trim(new.raw_user_meta_data->>'display_name'), ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'Guild member'
    ), 60)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();
revoke all on function public.handle_new_user() from public, anon, authenticated;

insert into public.profiles (id, display_name)
select
  id,
  left(coalesce(
    nullif(trim(raw_user_meta_data->>'display_name'), ''),
    nullif(split_part(coalesce(email, ''), '@', 1), ''),
    'Guild member'
  ), 60)
from auth.users
on conflict (id) do nothing;

create table public.guilds (
  id uuid primary key default gen_random_uuid(),
  instance_key text not null unique default 'main' check (instance_key = 'main'),
  name text not null check (char_length(trim(name)) between 2 and 80),
  discord_server_id text unique check (discord_server_id is null or char_length(discord_server_id) between 1 and 32),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.guild_memberships (
  guild_id uuid not null references public.guilds(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'officer', 'member')),
  joined_at timestamptz not null default now(),
  primary key (guild_id, user_id)
);

create table public.guild_invites (
  id uuid primary key default gen_random_uuid(),
  guild_id uuid not null references public.guilds(id) on delete cascade,
  token_hash text not null unique,
  role text not null default 'member' check (role in ('member', 'officer')),
  created_by uuid not null references auth.users(id) on delete restrict,
  expires_at timestamptz not null default (now() + interval '7 days'),
  max_uses integer not null default 20 check (max_uses between 1 and 500),
  uses integer not null default 0 check (uses >= 0),
  created_at timestamptz not null default now()
);

-- Static Wrath specs validate that saved player class/spec pairs are real.
create table public.wow_specs (
  id text primary key,
  class_id text not null check (class_id in (
    'warrior', 'paladin', 'hunter', 'rogue', 'priest',
    'deathknight', 'shaman', 'mage', 'warlock', 'druid'
  )),
  name text not null,
  roles text[] not null check (cardinality(roles) between 1 and 2),
  unique (id, class_id)
);

insert into public.wow_specs (id, class_id, name, roles) values
  ('deathknight.blood', 'deathknight', 'Blood', array['tank', 'melee']),
  ('deathknight.frost', 'deathknight', 'Frost', array['melee', 'tank']),
  ('deathknight.unholy', 'deathknight', 'Unholy', array['melee', 'tank']),
  ('druid.balance', 'druid', 'Balance', array['ranged']),
  ('druid.feral', 'druid', 'Feral', array['melee', 'tank']),
  ('druid.restoration', 'druid', 'Restoration', array['healer']),
  ('hunter.beastmastery', 'hunter', 'Beast Mastery', array['ranged']),
  ('hunter.marksmanship', 'hunter', 'Marksmanship', array['ranged']),
  ('hunter.survival', 'hunter', 'Survival', array['ranged']),
  ('mage.arcane', 'mage', 'Arcane', array['ranged']),
  ('mage.fire', 'mage', 'Fire', array['ranged']),
  ('mage.frost', 'mage', 'Frost', array['ranged']),
  ('paladin.holy', 'paladin', 'Holy', array['healer']),
  ('paladin.protection', 'paladin', 'Protection', array['tank']),
  ('paladin.retribution', 'paladin', 'Retribution', array['melee']),
  ('priest.discipline', 'priest', 'Discipline', array['healer']),
  ('priest.holy', 'priest', 'Holy', array['healer']),
  ('priest.shadow', 'priest', 'Shadow', array['ranged']),
  ('rogue.assassination', 'rogue', 'Assassination', array['melee']),
  ('rogue.combat', 'rogue', 'Combat', array['melee']),
  ('rogue.subtlety', 'rogue', 'Subtlety', array['melee']),
  ('shaman.elemental', 'shaman', 'Elemental', array['ranged']),
  ('shaman.enhancement', 'shaman', 'Enhancement', array['melee']),
  ('shaman.restoration', 'shaman', 'Restoration', array['healer']),
  ('warlock.affliction', 'warlock', 'Affliction', array['ranged']),
  ('warlock.demonology', 'warlock', 'Demonology', array['ranged']),
  ('warlock.destruction', 'warlock', 'Destruction', array['ranged']),
  ('warrior.arms', 'warrior', 'Arms', array['melee']),
  ('warrior.fury', 'warrior', 'Fury', array['melee']),
  ('warrior.protection', 'warrior', 'Protection', array['tank']);

-- This is the shared guild-wide player library. Raid state records a snapshot
-- of each player's spec and role so characters can still vary per raid.
create table public.guild_players (
  guild_id uuid not null references public.guilds(id) on delete cascade,
  id text not null check (char_length(id) between 1 and 80),
  name text not null check (char_length(trim(name)) between 1 and 24),
  class_id text not null check (class_id in (
    'warrior', 'paladin', 'hunter', 'rogue', 'priest',
    'deathknight', 'shaman', 'mage', 'warlock', 'druid'
  )),
  spec_id text not null check (char_length(spec_id) between 3 and 48),
  role text not null check (role in ('tank', 'healer', 'melee', 'ranged')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (guild_id, id),
  foreign key (spec_id, class_id) references public.wow_specs(id, class_id)
);

-- Raid planner state is stored as one JSONB aggregate to preserve the exact
-- client model (title, size, roster, and the 5 x 5 group/slot matrix).
create table public.raids (
  id uuid primary key default gen_random_uuid(),
  guild_id uuid not null references public.guilds(id) on delete cascade,
  title text not null default 'New raid' check (char_length(trim(title)) between 1 and 60),
  size smallint not null default 25 check (size in (10, 25)),
  state jsonb not null default '{"title":"New raid","size":25,"roster":[],"groups":[[null,null,null,null,null],[null,null,null,null,null],[null,null,null,null,null],[null,null,null,null,null],[null,null,null,null,null]]}'::jsonb,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (guild_id, id),
  check (jsonb_typeof(state->'roster') = 'array'),
  check (jsonb_typeof(state->'groups') = 'array'),
  check (jsonb_array_length(state->'groups') = 5)
);

create index guild_memberships_user_idx on public.guild_memberships(user_id);
create index guild_players_name_idx on public.guild_players(guild_id, lower(name));
create index raids_guild_updated_idx on public.raids(guild_id, updated_at desc);
create index guild_invites_guild_idx on public.guild_invites(guild_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger guilds_set_updated_at
before update on public.guilds
for each row execute function public.set_updated_at();

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger guild_players_set_updated_at
before update on public.guild_players
for each row execute function public.set_updated_at();

create trigger raids_set_updated_at
before update on public.raids
for each row execute function public.set_updated_at();

create or replace function public.validate_guild_player_spec()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.wow_specs ws
    where ws.id = new.spec_id
      and ws.class_id = new.class_id
      and new.role = any (ws.roles)
  ) then
    raise exception 'Invalid class, specialization, or role combination.' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger guild_players_validate_spec
before insert or update of class_id, spec_id, role on public.guild_players
for each row execute function public.validate_guild_player_spec();

revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on function public.validate_guild_player_spec() from public, anon, authenticated;

-- SECURITY DEFINER helpers avoid recursive RLS evaluation on memberships.
create or replace function public.is_guild_member(p_guild_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.guild_memberships gm
    where gm.guild_id = p_guild_id and gm.user_id = (select auth.uid())
  );
$$;

create or replace function public.has_guild_role(p_guild_id uuid, p_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.guild_memberships gm
    where gm.guild_id = p_guild_id
      and gm.user_id = (select auth.uid())
      and gm.role = any (p_roles)
  );
$$;

revoke all on function public.is_guild_member(uuid) from public, anon;
revoke all on function public.has_guild_role(uuid, text[]) from public, anon;
grant execute on function public.is_guild_member(uuid) to authenticated;
grant execute on function public.has_guild_role(uuid, text[]) to authenticated;

-- The first authenticated user creates the single workspace and becomes owner.
create or replace function public.create_guild(p_name text, p_discord_server_id text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_guild_id uuid;
begin
  if v_user_id is null then
    raise exception 'You must be signed in to create a guild.' using errcode = '42501';
  end if;
  if exists (select 1 from public.guilds) then
    raise exception 'This Supabase project already has its guild workspace.' using errcode = '23505';
  end if;

  insert into public.guilds (name, discord_server_id, created_by)
  values (trim(p_name), nullif(trim(p_discord_server_id), ''), v_user_id)
  returning id into v_guild_id;

  insert into public.guild_memberships (guild_id, user_id, role)
  values (v_guild_id, v_user_id, 'owner');
  return v_guild_id;
end;
$$;

-- Invite tokens are returned once; only their SHA-256 hashes are stored.
create or replace function public.create_guild_invite(
  p_guild_id uuid,
  p_role text default 'member',
  p_max_uses integer default 20
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_token text;
begin
  if not public.has_guild_role(p_guild_id, array['owner', 'admin', 'officer']) then
    raise exception 'Only guild officers can create invites.' using errcode = '42501';
  end if;
  if p_role not in ('member', 'officer') then
    raise exception 'Invite role must be member or officer.' using errcode = '22023';
  end if;
  if p_role = 'officer' and not public.has_guild_role(p_guild_id, array['owner', 'admin']) then
    raise exception 'Only owners and admins can invite officers.' using errcode = '42501';
  end if;
  if p_max_uses not between 1 and 500 then
    raise exception 'Invite use limit must be between 1 and 500.' using errcode = '22023';
  end if;

  v_token := encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.guild_invites (guild_id, token_hash, role, created_by, max_uses)
  values (
    p_guild_id,
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    p_role,
    v_user_id,
    p_max_uses
  );
  return v_token;
end;
$$;

create or replace function public.join_guild(p_invite_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_invite public.guild_invites%rowtype;
begin
  if v_user_id is null then
    raise exception 'You must be signed in to join a guild.' using errcode = '42501';
  end if;
  if exists (select 1 from public.guild_memberships where user_id = v_user_id) then
    raise exception 'Your account already belongs to a guild.' using errcode = '23505';
  end if;

  select * into v_invite
  from public.guild_invites
  where token_hash = encode(extensions.digest(trim(p_invite_code), 'sha256'), 'hex')
  for update;

  if not found or v_invite.expires_at <= now() or v_invite.uses >= v_invite.max_uses then
    raise exception 'This invite is invalid, expired, or fully used.' using errcode = '22023';
  end if;

  insert into public.guild_memberships (guild_id, user_id, role)
  values (v_invite.guild_id, v_user_id, v_invite.role);
  update public.guild_invites set uses = uses + 1 where id = v_invite.id;
  return v_invite.guild_id;
end;
$$;

create or replace function public.update_guild_member_role(
  p_guild_id uuid,
  p_user_id uuid,
  p_role text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_guild_role(p_guild_id, array['owner', 'admin']) then
    raise exception 'Only owners and admins can change member roles.' using errcode = '42501';
  end if;
  if p_role not in ('admin', 'officer', 'member') then
    raise exception 'Role must be admin, officer, or member.' using errcode = '22023';
  end if;
  update public.guild_memberships
  set role = p_role
  where guild_id = p_guild_id and user_id = p_user_id and role <> 'owner';
  if not found then
    raise exception 'Member not found or owner role cannot be changed here.' using errcode = 'P0002';
  end if;
end;
$$;

-- Saves one raid atomically and mirrors its characters into the guild roster.
create or replace function public.save_raid(p_guild_id uuid, p_raid_id uuid, p_state jsonb)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_raid_id uuid := coalesce(p_raid_id, extensions.gen_random_uuid());
  v_character jsonb;
begin
  if not public.has_guild_role(p_guild_id, array['owner', 'admin', 'officer']) then
    raise exception 'Only guild officers can create or edit raids.' using errcode = '42501';
  end if;
  if jsonb_typeof(p_state->'roster') is distinct from 'array'
     or jsonb_typeof(p_state->'groups') is distinct from 'array'
     or jsonb_array_length(p_state->'groups') <> 5
     or (p_state->>'size')::smallint not in (10, 25)
     or char_length(trim(coalesce(p_state->>'title', ''))) not between 1 and 60 then
    raise exception 'Invalid raid state.' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_state->'groups') as group_slots(value)
    where jsonb_typeof(group_slots.value) is distinct from 'array'
       or jsonb_array_length(group_slots.value) <> 5
  ) then
    raise exception 'Each raid group must contain exactly five slots.' using errcode = '22023';
  end if;
  if exists (
    select character.value->>'id'
    from jsonb_array_elements(p_state->'roster') as character(value)
    group by character.value->>'id'
    having character.value->>'id' is null or count(*) > 1
  ) then
    raise exception 'Raid roster character IDs must be present and unique.' using errcode = '22023';
  end if;
  if exists (
    select slot.value
    from jsonb_array_elements(p_state->'groups') as group_slots(value)
    cross join jsonb_array_elements(group_slots.value) as slot(value)
    where slot.value <> 'null'::jsonb
    group by slot.value
    having count(*) > 1
  ) then
    raise exception 'A character cannot occupy more than one raid slot.' using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_state->'groups') as group_slots(value)
    cross join jsonb_array_elements(group_slots.value) as slot(value)
    where slot.value <> 'null'::jsonb
      and not exists (
        select 1 from jsonb_array_elements(p_state->'roster') as character(value)
        where character.value->'id' = slot.value
      )
  ) then
    raise exception 'Raid slots must reference characters in the raid roster.' using errcode = '22023';
  end if;

  insert into public.raids (id, guild_id, title, size, state, created_by, updated_by)
  values (
    v_raid_id, p_guild_id, trim(p_state->>'title'),
    (p_state->>'size')::smallint, p_state, v_user_id, v_user_id
  )
  on conflict (id) do update set
    title = excluded.title,
    size = excluded.size,
    state = excluded.state,
    updated_by = v_user_id,
    updated_at = now()
  where public.raids.guild_id = p_guild_id;

  if not found then
    raise exception 'Raid not found in this guild.' using errcode = 'P0002';
  end if;

  for v_character in select value from jsonb_array_elements(p_state->'roster')
  loop
    insert into public.guild_players (guild_id, id, name, class_id, spec_id, role, created_by)
    values (
      p_guild_id,
      v_character->>'id',
      trim(v_character->>'name'),
      v_character->>'classId',
      v_character->>'specId',
      v_character->>'role',
      v_user_id
    )
    on conflict (guild_id, id) do update set
      name = excluded.name,
      class_id = excluded.class_id,
      spec_id = excluded.spec_id,
      role = excluded.role,
      updated_at = now();
  end loop;

  return v_raid_id;
end;
$$;

revoke all on function public.create_guild(text, text) from public, anon;
revoke all on function public.create_guild_invite(uuid, text, integer) from public, anon;
revoke all on function public.join_guild(text) from public, anon;
revoke all on function public.update_guild_member_role(uuid, uuid, text) from public, anon;
revoke all on function public.save_raid(uuid, uuid, jsonb) from public, anon;
grant execute on function public.create_guild(text, text) to authenticated;
grant execute on function public.create_guild_invite(uuid, text, integer) to authenticated;
grant execute on function public.join_guild(text) to authenticated;
grant execute on function public.update_guild_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.save_raid(uuid, uuid, jsonb) to authenticated;

alter table public.profiles enable row level security;
alter table public.guilds enable row level security;
alter table public.guild_memberships enable row level security;
alter table public.guild_invites enable row level security;
alter table public.guild_players enable row level security;
alter table public.raids enable row level security;
alter table public.wow_specs enable row level security;

revoke all on public.profiles, public.guilds, public.guild_memberships, public.guild_invites, public.guild_players, public.raids, public.wow_specs
  from public, anon, authenticated;
grant usage on schema public to authenticated;
grant select on public.profiles, public.guilds, public.guild_memberships, public.guild_players, public.raids, public.wow_specs to authenticated;
grant update (display_name, updated_at) on public.profiles to authenticated;
grant insert (guild_id, id, name, class_id, spec_id, role, created_by)
  on public.guild_players to authenticated;
grant update (name, class_id, spec_id, role, updated_at)
  on public.guild_players to authenticated;
grant delete on public.guild_players to authenticated;
grant insert (id, guild_id, title, size, state, created_by, updated_by)
  on public.raids to authenticated;
grant update (title, size, state, updated_by, updated_at)
  on public.raids to authenticated;
grant delete on public.raids to authenticated;

create policy "Guild members can view their guild"
on public.guilds for select to authenticated
using (public.is_guild_member(id));

create policy "Users can view their own profile and guildmates' names"
on public.profiles for select to authenticated
using (
  id = (select auth.uid())
  or exists (
    select 1 from public.guild_memberships gm
    where gm.user_id = profiles.id and public.is_guild_member(gm.guild_id)
  )
);

create policy "Users can update their own profile"
on public.profiles for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy "Officers can update guild details"
on public.guilds for update to authenticated
using (public.has_guild_role(id, array['owner', 'admin', 'officer']))
with check (public.has_guild_role(id, array['owner', 'admin', 'officer']));

create policy "Guild members can view memberships"
on public.guild_memberships for select to authenticated
using (public.is_guild_member(guild_id));

create policy "Authenticated users can view the game spec catalogue"
on public.wow_specs for select to authenticated
using (true);

create policy "Guild members can view the shared player roster"
on public.guild_players for select to authenticated
using (public.is_guild_member(guild_id));

create policy "Officers can add players to the shared roster"
on public.guild_players for insert to authenticated
with check (
  public.has_guild_role(guild_id, array['owner', 'admin', 'officer'])
  and created_by = (select auth.uid())
);

create policy "Officers can edit the shared player roster"
on public.guild_players for update to authenticated
using (public.has_guild_role(guild_id, array['owner', 'admin', 'officer']))
with check (public.has_guild_role(guild_id, array['owner', 'admin', 'officer']));

create policy "Officers can remove players from the shared roster"
on public.guild_players for delete to authenticated
using (public.has_guild_role(guild_id, array['owner', 'admin', 'officer']));

create policy "Guild members can view raids"
on public.raids for select to authenticated
using (public.is_guild_member(guild_id));

create policy "Officers can create raids"
on public.raids for insert to authenticated
with check (
  public.has_guild_role(guild_id, array['owner', 'admin', 'officer'])
  and created_by = (select auth.uid())
  and updated_by = (select auth.uid())
);

create policy "Officers can edit raids"
on public.raids for update to authenticated
using (public.has_guild_role(guild_id, array['owner', 'admin', 'officer']))
with check (
  public.has_guild_role(guild_id, array['owner', 'admin', 'officer'])
  and updated_by = (select auth.uid())
);

create policy "Officers can delete raids"
on public.raids for delete to authenticated
using (public.has_guild_role(guild_id, array['owner', 'admin', 'officer']));

-- There are intentionally no direct client policies for guild_invites or
-- guild_memberships writes; narrowly-scoped RPCs perform those operations.
