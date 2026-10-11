-- Include saved raids (read-only) in the public guild view.
create or replace function public.get_public_guild_view(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if p_token is null or char_length(trim(p_token)) <> 64 then
    return null;
  end if;

  select jsonb_build_object(
    'guild', jsonb_build_object('name', guild.name),
    'currentRound', board.current_round,
    'raids', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', raid.id,
        'title', raid.title,
        'state', raid.state,
        'updatedAt', raid.updated_at
      ) order by raid.updated_at desc)
      from public.raids raid
      where raid.guild_id = guild.id
    ), '[]'::jsonb),
    'players', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', player.id,
        'name', player.name,
        'classId', player.class_id,
        'specId', player.spec_id,
        'role', player.role
      ) order by lower(player.name), player.id)
      from public.guild_players player
      where player.guild_id = guild.id
    ), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', item.id,
        'itemId', item.item_id,
        'name', item.item_name,
        'iconKey', item.icon_key,
        'copies', item.copies,
        'note', item.note,
        'candidates', coalesce((
          select jsonb_agg(jsonb_build_object(
            'playerId', candidate.player_id,
            'priority', candidate.priority,
            'status', candidate.status
          ) order by candidate.priority, lower(player.name), player.id)
          from public.loot_candidates candidate
          join public.guild_players player
            on player.guild_id = candidate.guild_id and player.id = candidate.player_id
          where candidate.guild_id = item.guild_id
            and candidate.board_id = item.board_id
            and candidate.item_id = item.id
        ), '[]'::jsonb),
        'awards', coalesce((
          select jsonb_agg(jsonb_build_object(
            'playerId', award.player_id,
            'round', award.round_number,
            'priority', award.priority_snapshot,
            'manualOverride', award.manual_override,
            'overrideReason', award.override_reason,
            'awardedAt', award.awarded_at,
            'voidedAt', award.voided_at,
            'voidReason', award.void_reason
          ) order by award.awarded_at desc)
          from public.loot_awards award
          where award.guild_id = item.guild_id
            and award.board_id = item.board_id
            and award.item_id = item.id
        ), '[]'::jsonb)
      ) order by lower(item.item_name), item.id)
      from public.loot_items item
      where item.guild_id = guild.id and item.board_id = board.id
    ), '[]'::jsonb)
  ) into v_result
  from public.guild_public_shares share
  join public.guilds guild on guild.id = share.guild_id
  join public.guild_loot_boards board on board.guild_id = guild.id
  where share.token_hash = encode(extensions.digest(trim(p_token), 'sha256'), 'hex')
    and share.revoked_at is null;

  return v_result;
end;
$$;
