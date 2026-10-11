-- Allow multiple candidates to share the same rank and roll for an award.

drop function public.reorder_loot_candidates(uuid, uuid, text[]);

create or replace function public.reorder_loot_candidates(
  p_guild_id uuid,
  p_item_id uuid,
  p_player_ids text[],
  p_priorities integer[]
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

  select * into v_item
  from public.loot_items
  where guild_id = p_guild_id and id = p_item_id
  for update;
  if not found then
    raise exception 'Loot item not found.' using errcode = 'P0002';
  end if;

  if not exists (
    select 1 from public.guild_loot_boards
    where guild_id = p_guild_id and id = v_item.board_id and status = 'active'
  ) then
    raise exception 'The guild loot board is not active.' using errcode = '23514';
  end if;

  select count(*) into v_count
  from public.loot_candidates
  where guild_id = p_guild_id and board_id = v_item.board_id and item_id = p_item_id;

  if cardinality(p_player_ids) is distinct from v_count
     or cardinality(p_priorities) is distinct from v_count
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

  if v_count > 0 and p_priorities[1] <> 1 then
    raise exception 'Priority ranks must start at 1.' using errcode = '22023';
  end if;

  for v_index in 1..v_count loop
    if p_priorities[v_index] < 1 then
      raise exception 'Priority ranks must be positive.' using errcode = '22023';
    end if;
    if v_index > 1 and (
      p_priorities[v_index] < p_priorities[v_index - 1]
      or p_priorities[v_index] > p_priorities[v_index - 1] + 1
    ) then
      raise exception 'Priorities must be ordered and may only tie or advance by one rank.' using errcode = '22023';
    end if;

    update public.loot_candidates
    set priority = p_priorities[v_index]
    where guild_id = p_guild_id and board_id = v_item.board_id
      and item_id = p_item_id and player_id = p_player_ids[v_index];
  end loop;
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
  v_top_priority integer;
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
  where guild_id = p_guild_id and board_id = p_board_id
    and item_id = p_item_id and voided_at is null;
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

    select min(candidate.priority) into v_top_priority
    from public.loot_candidates candidate
    where candidate.guild_id = p_guild_id and candidate.board_id = p_board_id
      and candidate.item_id = p_item_id and candidate.status = 'active'
      and not exists (
        select 1 from public.loot_awards award
        where award.guild_id = p_guild_id and award.board_id = p_board_id
          and award.player_id = candidate.player_id
          and award.round_number = v_board.current_round and award.voided_at is null
      );

    if v_top_priority is null or v_priority <> v_top_priority then
      raise exception 'Award a player in the highest eligible priority group, or use an override with a reason.' using errcode = '23514';
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

revoke all on function public.reorder_loot_candidates(uuid, uuid, text[], integer[]) from public, anon;
grant execute on function public.reorder_loot_candidates(uuid, uuid, text[], integer[]) to authenticated;
revoke all on function public.record_loot_award(uuid, uuid, uuid, text, boolean, text) from public, anon;
grant execute on function public.record_loot_award(uuid, uuid, uuid, text, boolean, text) to authenticated;
