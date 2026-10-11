-- Convert each guild's loot session into its one permanent, all-time loot board.
-- Rename in place so existing items, priorities, awards, and round state survive.

drop function public.record_loot_award(uuid, uuid, uuid, text, boolean, text);
drop function public.advance_loot_round(uuid, uuid);
drop function public.void_loot_award(uuid, uuid, text);
drop function public.reorder_loot_candidates(uuid, uuid, text[]);

alter table public.loot_sessions rename to guild_loot_boards;
alter table public.loot_items rename column session_id to board_id;
alter table public.loot_candidates rename column session_id to board_id;
alter table public.loot_awards rename column session_id to board_id;

-- This app installation is for exactly one guild, so it has one permanent board.
create unique index guild_loot_boards_one_per_guild_idx on public.guild_loot_boards(guild_id);
update public.guild_loot_boards set title = 'Guild Loot Board', status = 'active';

insert into public.guild_loot_boards (guild_id, title, status, created_by)
select guild.id, 'Guild Loot Board', 'active', guild.created_by
from public.guilds guild
where not exists (
  select 1 from public.guild_loot_boards board where board.guild_id = guild.id
)
on conflict (guild_id) do nothing;

drop policy "Guild members can view loot sessions" on public.guild_loot_boards;
drop policy "Officers can create loot sessions" on public.guild_loot_boards;
drop policy "Officers can update loot sessions" on public.guild_loot_boards;

revoke all on public.guild_loot_boards from public, anon, authenticated;
grant select on public.guild_loot_boards to authenticated;

create policy "Guild members can view the permanent loot board"
on public.guild_loot_boards for select to authenticated
using (public.is_guild_member(guild_id));

create or replace function public.create_guild_loot_board_on_guild_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.guild_loot_boards (guild_id, title, status, created_by)
  values (new.id, 'Guild Loot Board', 'active', new.created_by)
  on conflict (guild_id) do nothing;
  return new;
end;
$$;

revoke all on function public.create_guild_loot_board_on_guild_insert() from public, anon, authenticated;
create trigger guilds_create_permanent_loot_board
after insert on public.guilds
for each row execute function public.create_guild_loot_board_on_guild_insert();

-- Board creation is automatic on first officer visit; there is no session picker.
create or replace function public.ensure_guild_loot_board(p_guild_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_board_id uuid;
  v_user_id uuid := (select auth.uid());
begin
  if not public.has_guild_role(p_guild_id, array['owner', 'admin', 'officer']) then
    raise exception 'Only guild officers can initialize the loot board.' using errcode = '42501';
  end if;

  insert into public.guild_loot_boards (guild_id, title, status, created_by)
  values (p_guild_id, 'Guild Loot Board', 'active', v_user_id)
  on conflict (guild_id) do nothing;

  select id into v_board_id
  from public.guild_loot_boards
  where guild_id = p_guild_id;
  return v_board_id;
end;
$$;

create or replace function public.record_loot_award(
  p_guild_id uuid,
  p_board_id uuid,
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
  v_board public.guild_loot_boards%rowtype;
  v_item public.loot_items%rowtype;
  v_priority integer;
  v_top_player text;
  v_award_id uuid;
  v_awarded_copies integer;
begin
  if not public.has_guild_role(p_guild_id, array['owner', 'admin', 'officer']) then
    raise exception 'Only guild officers can award loot.' using errcode = '42501';
  end if;

  select * into v_board
  from public.guild_loot_boards
  where guild_id = p_guild_id and id = p_board_id
  for update;
  if not found or v_board.status <> 'active' then
    raise exception 'Guild loot board not found or inactive.' using errcode = 'P0002';
  end if;

  select * into v_item
  from public.loot_items
  where guild_id = p_guild_id and board_id = p_board_id and id = p_item_id
  for update;
  if not found then
    raise exception 'Loot item not found on this board.' using errcode = 'P0002';
  end if;

  select count(*) into v_awarded_copies
  from public.loot_awards
  where guild_id = p_guild_id and board_id = p_board_id and item_id = p_item_id
    and voided_at is null;
  if v_awarded_copies >= v_item.copies then
    raise exception 'All copies of this item have already been awarded.' using errcode = '23514';
  end if;

  select priority into v_priority
  from public.loot_candidates
  where guild_id = p_guild_id and board_id = p_board_id
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
      where guild_id = p_guild_id and board_id = p_board_id
        and player_id = p_player_id and round_number = v_board.current_round
        and voided_at is null
    ) then
      raise exception 'This player already received loot in the current round.' using errcode = '23514';
    end if;

    select candidate.player_id into v_top_player
    from public.loot_candidates candidate
    where candidate.guild_id = p_guild_id and candidate.board_id = p_board_id
      and candidate.item_id = p_item_id and candidate.status = 'active'
      and not exists (
        select 1 from public.loot_awards award
        where award.guild_id = p_guild_id and award.board_id = p_board_id
          and award.player_id = candidate.player_id
          and award.round_number = v_board.current_round
          and award.voided_at is null
      )
    order by candidate.priority, candidate.created_at, candidate.id
    limit 1;
    if v_top_player is distinct from p_player_id then
      raise exception 'Award the highest-priority eligible player, or use an override with a reason.' using errcode = '23514';
    end if;
  end if;

  insert into public.loot_awards (
    guild_id, board_id, item_id, player_id, round_number,
    priority_snapshot, manual_override, override_reason, awarded_by
  ) values (
    p_guild_id, p_board_id, p_item_id, p_player_id, v_board.current_round,
    v_priority, p_manual_override,
    case when p_manual_override then trim(p_override_reason) else null end,
    v_user_id
  ) returning id into v_award_id;

  return v_award_id;
end;
$$;

create or replace function public.advance_loot_round(p_guild_id uuid, p_board_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_board public.guild_loot_boards%rowtype;
begin
  if not public.has_guild_role(p_guild_id, array['owner', 'admin', 'officer']) then
    raise exception 'Only guild officers can advance the loot round.' using errcode = '42501';
  end if;

  select * into v_board
  from public.guild_loot_boards
  where guild_id = p_guild_id and id = p_board_id
  for update;
  if not found or v_board.status <> 'active' then
    raise exception 'Guild loot board not found or inactive.' using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from public.loot_items item
    join public.loot_candidates candidate
      on candidate.guild_id = item.guild_id
      and candidate.board_id = item.board_id
      and candidate.item_id = item.id
      and candidate.status = 'active'
    where item.guild_id = p_guild_id and item.board_id = p_board_id
      and (select count(*) from public.loot_awards award
        where award.guild_id = item.guild_id and award.board_id = item.board_id
          and award.item_id = item.id and award.voided_at is null) < item.copies
      and not exists (
        select 1 from public.loot_awards award
        where award.guild_id = p_guild_id and award.board_id = p_board_id
          and award.player_id = candidate.player_id
          and award.round_number = v_board.current_round
          and award.voided_at is null
      )
  ) then
    raise exception 'Eligible candidates remain. Award or pass them before advancing.' using errcode = '23514';
  end if;

  update public.guild_loot_boards
  set current_round = current_round + 1, updated_at = now()
  where guild_id = p_guild_id and id = p_board_id
  returning current_round into v_board.current_round;
  return v_board.current_round;
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

  perform 1 from public.guild_loot_boards
  where guild_id = p_guild_id and id = v_award.board_id for update;
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
  where guild_id = p_guild_id and board_id = v_item.board_id and item_id = p_item_id;
  if cardinality(p_player_ids) is distinct from v_count
     or (select count(distinct player_id) from unnest(p_player_ids) as ids(player_id)) <> v_count
     or exists (
       select 1 from unnest(p_player_ids) as ids(player_id)
       where not exists (
         select 1 from public.loot_candidates candidate
         where candidate.guild_id = p_guild_id and candidate.board_id = v_item.board_id
           and candidate.item_id = p_item_id and candidate.player_id = ids.player_id
       )
     ) then
    raise exception 'Priority order must include each candidate exactly once.' using errcode = '22023';
  end if;

  for v_index in 1..v_count loop
    update public.loot_candidates
    set priority = v_index
    where guild_id = p_guild_id and board_id = v_item.board_id
      and item_id = p_item_id and player_id = p_player_ids[v_index];
  end loop;
end;
$$;

revoke all on function public.ensure_guild_loot_board(uuid) from public, anon;
revoke all on function public.record_loot_award(uuid, uuid, uuid, text, boolean, text) from public, anon;
revoke all on function public.advance_loot_round(uuid, uuid) from public, anon;
revoke all on function public.void_loot_award(uuid, uuid, text) from public, anon;
revoke all on function public.reorder_loot_candidates(uuid, uuid, text[]) from public, anon;
grant execute on function public.ensure_guild_loot_board(uuid) to authenticated;
grant execute on function public.record_loot_award(uuid, uuid, uuid, text, boolean, text) to authenticated;
grant execute on function public.advance_loot_round(uuid, uuid) to authenticated;
grant execute on function public.void_loot_award(uuid, uuid, text) to authenticated;
grant execute on function public.reorder_loot_candidates(uuid, uuid, text[]) to authenticated;
