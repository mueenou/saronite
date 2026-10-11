-- Apply loot awards recorded in game by the Saronite WeakAura, atomically.
-- p_awards: ordered array of { itemId uuid, playerId text, round int, override bool }.
-- The in-game aura already decided round changes, so rounds are moved forward
-- to match without the usual "eligible candidates remain" check.

create or replace function public.import_weakaura_loot(
  p_guild_id uuid,
  p_board_id uuid,
  p_awards jsonb,
  p_final_round integer
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_board public.guild_loot_boards%rowtype;
  v_award jsonb;
  v_item public.loot_items%rowtype;
  v_priority integer;
  v_round integer;
  v_override boolean;
  v_count integer := 0;
begin
  if not public.has_guild_role(p_guild_id, array['owner', 'admin', 'officer']) then
    raise exception 'Only guild officers can import loot.' using errcode = '42501';
  end if;

  if jsonb_typeof(p_awards) <> 'array' then
    raise exception 'Invalid award list.' using errcode = '22023';
  end if;

  select * into v_board
  from public.guild_loot_boards
  where guild_id = p_guild_id and id = p_board_id
  for update;
  if not found or v_board.status <> 'active' then
    raise exception 'Guild loot board not found or inactive.' using errcode = 'P0002';
  end if;

  for v_award in select value from jsonb_array_elements(p_awards)
  loop
    v_round := greatest(coalesce((v_award->>'round')::integer, v_board.current_round), v_board.current_round);
    v_override := coalesce((v_award->>'override')::boolean, false);

    if v_round > v_board.current_round then
      update public.guild_loot_boards set current_round = v_round, updated_at = now()
      where guild_id = p_guild_id and id = p_board_id;
      v_board.current_round := v_round;
    end if;

    select * into v_item
    from public.loot_items
    where guild_id = p_guild_id and board_id = p_board_id and id = (v_award->>'itemId')::uuid
    for update;
    if not found then
      raise exception 'Loot item not found on this board.' using errcode = 'P0002';
    end if;

    if (select count(*) from public.loot_awards
        where guild_id = p_guild_id and board_id = p_board_id
          and item_id = v_item.id and voided_at is null) >= v_item.copies then
      raise exception 'All copies of % have already been awarded.', v_item.item_name using errcode = '23514';
    end if;

    select priority into v_priority
    from public.loot_candidates
    where guild_id = p_guild_id and board_id = p_board_id
      and item_id = v_item.id and player_id = v_award->>'playerId';
    if not found then
      raise exception 'A player is not on the priority list for %.', v_item.item_name using errcode = 'P0002';
    end if;

    insert into public.loot_awards (
      guild_id, board_id, item_id, player_id, round_number,
      priority_snapshot, manual_override, override_reason, awarded_by
    ) values (
      p_guild_id, p_board_id, v_item.id, v_award->>'playerId', v_board.current_round,
      v_priority, v_override,
      case when v_override then 'Recorded in game (WeakAura import)' else null end,
      v_user_id
    );
    v_count := v_count + 1;
  end loop;

  if p_final_round is not null and p_final_round > v_board.current_round then
    update public.guild_loot_boards set current_round = p_final_round, updated_at = now()
    where guild_id = p_guild_id and id = p_board_id;
  end if;

  return v_count;
end;
$$;

revoke all on function public.import_weakaura_loot(uuid, uuid, jsonb, integer) from public, anon;
grant execute on function public.import_weakaura_loot(uuid, uuid, jsonb, integer) to authenticated;
