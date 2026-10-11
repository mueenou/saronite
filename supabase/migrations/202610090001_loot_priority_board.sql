-- Guild-scoped loot attribution board with one-loot-per-player round priority.

create table public.loot_sessions (
  id uuid primary key default gen_random_uuid(),
  guild_id uuid not null references public.guilds(id) on delete cascade,
  raid_id uuid references public.raids(id) on delete set null,
  title text not null check (char_length(trim(title)) between 1 and 80),
  status text not null default 'active' check (status in ('active', 'closed')),
  current_round integer not null default 1 check (current_round > 0),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (guild_id, id)
);

create table public.loot_items (
  id uuid primary key default gen_random_uuid(),
  guild_id uuid not null,
  session_id uuid not null,
  item_id bigint check (item_id is null or item_id > 0),
  item_name text not null check (char_length(trim(item_name)) between 1 and 100),
  icon_key text not null default 'inv_misc_questionmark'
    check (icon_key ~ '^[a-z0-9_]{1,80}$'),
  copies smallint not null default 1 check (copies between 1 and 20),
  note text not null default '' check (char_length(note) <= 500),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (guild_id, session_id, id),
  foreign key (guild_id, session_id) references public.loot_sessions(guild_id, id) on delete cascade
);

create table public.loot_candidates (
  id uuid primary key default gen_random_uuid(),
  guild_id uuid not null,
  session_id uuid not null,
  item_id uuid not null,
  player_id text not null,
  priority integer not null check (priority > 0),
  status text not null default 'active' check (status in ('active', 'passed')),
  created_at timestamptz not null default now(),
  unique (guild_id, session_id, item_id, id),
  unique (guild_id, session_id, item_id, player_id),
  foreign key (guild_id, session_id, item_id)
    references public.loot_items(guild_id, session_id, id) on delete cascade,
  foreign key (guild_id, player_id)
    references public.guild_players(guild_id, id) on delete restrict
);

create table public.loot_awards (
  id uuid primary key default gen_random_uuid(),
  guild_id uuid not null,
  session_id uuid not null,
  item_id uuid not null,
  player_id text not null,
  round_number integer not null check (round_number > 0),
  priority_snapshot integer not null check (priority_snapshot > 0),
  manual_override boolean not null default false,
  override_reason text,
  awarded_by uuid not null references auth.users(id) on delete restrict,
  awarded_at timestamptz not null default now(),
  voided_at timestamptz,
  voided_by uuid references auth.users(id) on delete restrict,
  void_reason text,
  foreign key (guild_id, session_id, item_id)
    references public.loot_items(guild_id, session_id, id) on delete restrict,
  foreign key (guild_id, player_id)
    references public.guild_players(guild_id, id) on delete restrict,
  check (
    (manual_override and char_length(trim(coalesce(override_reason, ''))) between 5 and 500)
    or (not manual_override and override_reason is null)
  ),
  check (
    (voided_at is null and voided_by is null and void_reason is null)
    or (voided_at is not null and voided_by is not null and char_length(trim(coalesce(void_reason, ''))) between 5 and 500)
  )
);

create index loot_sessions_guild_created_idx on public.loot_sessions(guild_id, created_at desc);
create index loot_items_session_idx on public.loot_items(guild_id, session_id, created_at);
create index loot_candidates_priority_idx on public.loot_candidates(guild_id, session_id, item_id, priority);
create index loot_awards_session_round_idx on public.loot_awards(guild_id, session_id, round_number, awarded_at);

create trigger loot_sessions_set_updated_at
before update on public.loot_sessions
for each row execute function public.set_updated_at();

revoke all on public.loot_sessions, public.loot_items, public.loot_candidates, public.loot_awards
  from public, anon, authenticated;
grant select on public.loot_sessions, public.loot_items, public.loot_candidates, public.loot_awards to authenticated;
grant insert (guild_id, raid_id, title, status, created_by)
  on public.loot_sessions to authenticated;
grant update (raid_id, title, status, updated_at)
  on public.loot_sessions to authenticated;
grant insert (guild_id, session_id, item_id, item_name, icon_key, copies, note, created_by)
  on public.loot_items to authenticated;
grant update (item_id, item_name, icon_key, copies, note)
  on public.loot_items to authenticated;
grant delete on public.loot_items to authenticated;
grant insert (guild_id, session_id, item_id, player_id, priority, status)
  on public.loot_candidates to authenticated;
grant update (priority, status)
  on public.loot_candidates to authenticated;
grant delete on public.loot_candidates to authenticated;

alter table public.loot_sessions enable row level security;
alter table public.loot_items enable row level security;
alter table public.loot_candidates enable row level security;
alter table public.loot_awards enable row level security;

create policy "Guild members can view loot sessions"
on public.loot_sessions for select to authenticated
using (public.is_guild_member(guild_id));

create policy "Officers can create loot sessions"
on public.loot_sessions for insert to authenticated
with check (
  public.has_guild_role(guild_id, array['owner', 'admin', 'officer'])
  and created_by = (select auth.uid())
);

create policy "Officers can update loot sessions"
on public.loot_sessions for update to authenticated
using (public.has_guild_role(guild_id, array['owner', 'admin', 'officer']))
with check (public.has_guild_role(guild_id, array['owner', 'admin', 'officer']));

create policy "Guild members can view loot items"
on public.loot_items for select to authenticated
using (public.is_guild_member(guild_id));

create policy "Officers can add loot items"
on public.loot_items for insert to authenticated
with check (
  public.has_guild_role(guild_id, array['owner', 'admin', 'officer'])
  and created_by = (select auth.uid())
  and exists (
    select 1 from public.loot_sessions loot_session
    where loot_session.guild_id = loot_items.guild_id
      and loot_session.id = loot_items.session_id and loot_session.status = 'active'
  )
);

create policy "Officers can update loot items"
on public.loot_items for update to authenticated
using (public.has_guild_role(guild_id, array['owner', 'admin', 'officer']))
with check (
  public.has_guild_role(guild_id, array['owner', 'admin', 'officer'])
  and exists (
    select 1 from public.loot_sessions loot_session
    where loot_session.guild_id = loot_items.guild_id
      and loot_session.id = loot_items.session_id and loot_session.status = 'active'
  )
);

create policy "Officers can remove loot items without awards"
on public.loot_items for delete to authenticated
using (
  public.has_guild_role(guild_id, array['owner', 'admin', 'officer'])
  and exists (
    select 1 from public.loot_sessions loot_session
    where loot_session.guild_id = loot_items.guild_id
      and loot_session.id = loot_items.session_id and loot_session.status = 'active'
  )
);

create policy "Guild members can view loot candidates"
on public.loot_candidates for select to authenticated
using (public.is_guild_member(guild_id));

create policy "Officers can add loot candidates"
on public.loot_candidates for insert to authenticated
with check (
  public.has_guild_role(guild_id, array['owner', 'admin', 'officer'])
  and exists (
    select 1 from public.loot_sessions loot_session
    where loot_session.guild_id = loot_candidates.guild_id
      and loot_session.id = loot_candidates.session_id and loot_session.status = 'active'
  )
);

create policy "Officers can reorder or pass loot candidates"
on public.loot_candidates for update to authenticated
using (public.has_guild_role(guild_id, array['owner', 'admin', 'officer']))
with check (
  public.has_guild_role(guild_id, array['owner', 'admin', 'officer'])
  and exists (
    select 1 from public.loot_sessions loot_session
    where loot_session.guild_id = loot_candidates.guild_id
      and loot_session.id = loot_candidates.session_id and loot_session.status = 'active'
  )
);

create policy "Officers can remove loot candidates"
on public.loot_candidates for delete to authenticated
using (
  public.has_guild_role(guild_id, array['owner', 'admin', 'officer'])
  and exists (
    select 1 from public.loot_sessions loot_session
    where loot_session.guild_id = loot_candidates.guild_id
      and loot_session.id = loot_candidates.session_id and loot_session.status = 'active'
  )
);

create policy "Guild members can view the loot award audit"
on public.loot_awards for select to authenticated
using (public.is_guild_member(guild_id));

-- Award creation is RPC-only; clients cannot forge or edit audit entries.
create or replace function public.record_loot_award(
  p_guild_id uuid,
  p_session_id uuid,
  p_item_id uuid,
  p_player_id text,
  p_manual_override boolean default false,
  p_override_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_session public.loot_sessions%rowtype;
  v_item public.loot_items%rowtype;
  v_priority integer;
  v_top_player text;
  v_award_id uuid;
  v_awarded_copies integer;
begin
  if not public.has_guild_role(p_guild_id, array['owner', 'admin', 'officer']) then
    raise exception 'Only guild officers can award loot.' using errcode = '42501';
  end if;

  select * into v_session
  from public.loot_sessions
  where guild_id = p_guild_id and id = p_session_id
  for update;
  if not found or v_session.status <> 'active' then
    raise exception 'Loot session not found or closed.' using errcode = 'P0002';
  end if;

  select * into v_item
  from public.loot_items
  where guild_id = p_guild_id and session_id = p_session_id and id = p_item_id
  for update;
  if not found then
    raise exception 'Loot item not found in this session.' using errcode = 'P0002';
  end if;

  select count(*) into v_awarded_copies
  from public.loot_awards
  where guild_id = p_guild_id and session_id = p_session_id and item_id = p_item_id
    and voided_at is null;
  if v_awarded_copies >= v_item.copies then
    raise exception 'All copies of this item have already been awarded.' using errcode = '23514';
  end if;

  select priority into v_priority
  from public.loot_candidates
  where guild_id = p_guild_id and session_id = p_session_id
    and item_id = p_item_id and player_id = p_player_id and status = 'active';
  if not found then
    raise exception 'Player is not an active candidate for this item.' using errcode = 'P0002';
  end if;

  if p_manual_override then
    if char_length(trim(coalesce(p_override_reason, ''))) not between 5 and 500 then
      raise exception 'Manual overrides require a reason of at least five characters.' using errcode = '22023';
    end if;
  else
    if exists (
      select 1 from public.loot_awards
      where guild_id = p_guild_id and session_id = p_session_id
        and player_id = p_player_id and round_number = v_session.current_round
        and voided_at is null
    ) then
      raise exception 'This player already received loot in the current round.' using errcode = '23514';
    end if;

    select candidate.player_id into v_top_player
    from public.loot_candidates candidate
    where candidate.guild_id = p_guild_id and candidate.session_id = p_session_id
      and candidate.item_id = p_item_id and candidate.status = 'active'
      and not exists (
        select 1 from public.loot_awards award
        where award.guild_id = p_guild_id and award.session_id = p_session_id
          and award.player_id = candidate.player_id
          and award.round_number = v_session.current_round
          and award.voided_at is null
      )
    order by candidate.priority, candidate.created_at, candidate.id
    limit 1;
    if v_top_player is distinct from p_player_id then
      raise exception 'Award the highest-priority eligible player, or use an override with a reason.' using errcode = '23514';
    end if;
  end if;

  insert into public.loot_awards (
    guild_id, session_id, item_id, player_id, round_number,
    priority_snapshot, manual_override, override_reason, awarded_by
  ) values (
    p_guild_id, p_session_id, p_item_id, p_player_id, v_session.current_round,
    v_priority, p_manual_override,
    case when p_manual_override then trim(p_override_reason) else null end,
    v_user_id
  ) returning id into v_award_id;

  return v_award_id;
end;
$$;

create or replace function public.advance_loot_round(p_guild_id uuid, p_session_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.loot_sessions%rowtype;
begin
  if not public.has_guild_role(p_guild_id, array['owner', 'admin', 'officer']) then
    raise exception 'Only guild officers can advance the loot round.' using errcode = '42501';
  end if;

  select * into v_session
  from public.loot_sessions
  where guild_id = p_guild_id and id = p_session_id
  for update;
  if not found or v_session.status <> 'active' then
    raise exception 'Loot session not found or closed.' using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from public.loot_items item
    join public.loot_candidates candidate
      on candidate.guild_id = item.guild_id
      and candidate.session_id = item.session_id
      and candidate.item_id = item.id
      and candidate.status = 'active'
    where item.guild_id = p_guild_id and item.session_id = p_session_id
      and (select count(*) from public.loot_awards award
        where award.guild_id = item.guild_id and award.session_id = item.session_id
          and award.item_id = item.id and award.voided_at is null) < item.copies
      and not exists (
        select 1 from public.loot_awards award
        where award.guild_id = p_guild_id and award.session_id = p_session_id
          and award.player_id = candidate.player_id
          and award.round_number = v_session.current_round
          and award.voided_at is null
      )
  ) then
    raise exception 'Eligible candidates remain. Award or pass them before advancing.' using errcode = '23514';
  end if;

  update public.loot_sessions
  set current_round = current_round + 1, updated_at = now()
  where guild_id = p_guild_id and id = p_session_id
  returning current_round into v_session.current_round;
  return v_session.current_round;
end;
$$;

create or replace function public.void_loot_award(p_guild_id uuid, p_award_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_award public.loot_awards%rowtype;
begin
  if not public.has_guild_role(p_guild_id, array['owner', 'admin', 'officer']) then
    raise exception 'Only guild officers can correct a loot award.' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) not between 5 and 500 then
    raise exception 'Voiding an award requires a reason of at least five characters.' using errcode = '22023';
  end if;

  select * into v_award from public.loot_awards
  where guild_id = p_guild_id and id = p_award_id for update;
  if not found or v_award.voided_at is not null then
    raise exception 'Active loot award not found.' using errcode = 'P0002';
  end if;

  perform 1 from public.loot_sessions
  where guild_id = p_guild_id and id = v_award.session_id for update;
  update public.loot_awards
  set voided_at = now(), voided_by = (select auth.uid()), void_reason = trim(p_reason)
  where id = p_award_id;
end;
$$;

create or replace function public.reorder_loot_candidates(
  p_guild_id uuid,
  p_item_id uuid,
  p_player_ids text[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.loot_items%rowtype;
  v_count integer;
  v_index integer;
begin
  if not public.has_guild_role(p_guild_id, array['owner', 'admin', 'officer']) then
    raise exception 'Only guild officers can reorder loot priorities.' using errcode = '42501';
  end if;
  select * into v_item from public.loot_items
  where guild_id = p_guild_id and id = p_item_id for update;
  if not found then
    raise exception 'Loot item not found.' using errcode = 'P0002';
  end if;

  select count(*) into v_count from public.loot_candidates
  where guild_id = p_guild_id and session_id = v_item.session_id and item_id = p_item_id;
  if cardinality(p_player_ids) is distinct from v_count
     or (select count(distinct player_id) from unnest(p_player_ids) as ids(player_id)) <> v_count
     or exists (
       select 1 from unnest(p_player_ids) as ids(player_id)
       where not exists (
         select 1 from public.loot_candidates candidate
         where candidate.guild_id = p_guild_id and candidate.session_id = v_item.session_id
           and candidate.item_id = p_item_id and candidate.player_id = ids.player_id
       )
     ) then
    raise exception 'Priority order must include each candidate exactly once.' using errcode = '22023';
  end if;

  for v_index in 1..v_count loop
    update public.loot_candidates
    set priority = v_index
    where guild_id = p_guild_id and session_id = v_item.session_id
      and item_id = p_item_id and player_id = p_player_ids[v_index];
  end loop;
end;
$$;

revoke all on function public.record_loot_award(uuid, uuid, uuid, text, boolean, text) from public, anon;
revoke all on function public.advance_loot_round(uuid, uuid) from public, anon;
revoke all on function public.void_loot_award(uuid, uuid, text) from public, anon;
revoke all on function public.reorder_loot_candidates(uuid, uuid, text[]) from public, anon;
grant execute on function public.record_loot_award(uuid, uuid, uuid, text, boolean, text) to authenticated;
grant execute on function public.advance_loot_round(uuid, uuid) to authenticated;
grant execute on function public.void_loot_award(uuid, uuid, text) to authenticated;
grant execute on function public.reorder_loot_candidates(uuid, uuid, text[]) to authenticated;
