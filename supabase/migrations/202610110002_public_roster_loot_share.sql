-- Token-protected, read-only public view of one guild's roster and loot board.
-- Public visitors get data only through the guarded RPC, never direct table access.

create table public.guild_public_shares (
  guild_id uuid primary key references public.guilds(id) on delete cascade,
  token_hash text not null unique,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

alter table public.guild_public_shares enable row level security;
revoke all on public.guild_public_shares from public, anon, authenticated;

create or replace function public.create_guild_public_share(p_guild_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
begin
  if not public.has_guild_role(p_guild_id, array['owner', 'admin', 'officer']) then
    raise exception 'Only guild officers can create a public view link.' using errcode = '42501';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.guild_public_shares (guild_id, token_hash, created_by, created_at, revoked_at)
  values (p_guild_id, encode(extensions.digest(v_token, 'sha256'), 'hex'), (select auth.uid()), now(), null)
  on conflict (guild_id) do update set
    token_hash = excluded.token_hash,
    created_by = excluded.created_by,
    created_at = excluded.created_at,
    revoked_at = null;
  return v_token;
end;
$$;

create or replace function public.revoke_guild_public_share(p_guild_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_guild_role(p_guild_id, array['owner', 'admin', 'officer']) then
    raise exception 'Only guild officers can revoke a public view link.' using errcode = '42501';
  end if;

  update public.guild_public_shares
  set revoked_at = now()
  where guild_id = p_guild_id and revoked_at is null;
end;
$$;

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

revoke all on function public.create_guild_public_share(uuid) from public, anon;
revoke all on function public.revoke_guild_public_share(uuid) from public, anon;
revoke all on function public.get_public_guild_view(text) from public;
grant execute on function public.create_guild_public_share(uuid) to authenticated;
grant execute on function public.revoke_guild_public_share(uuid) to authenticated;
grant execute on function public.get_public_guild_view(text) to anon, authenticated;
