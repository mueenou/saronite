import type { ClassId, Role } from '#shared/types'

export type LootCandidateStatus = 'active' | 'passed'

export interface LootBoardRecord {
  id: string
  currentRound: number
  status: 'active' | 'closed'
}

export interface LootItemRecord {
  id: string
  itemId: number | null
  name: string
  iconKey: string
  copies: number
  note: string
}

export interface LootCandidateRecord {
  id: string
  itemId: string
  playerId: string
  priority: number
  status: LootCandidateStatus
}

export interface LootAwardRecord {
  id: string
  itemId: string
  playerId: string
  round: number
  priority: number
  manualOverride: boolean
  overrideReason: string | null
  awardedBy: string
  awardedAt: string
  voidedAt: string | null
  voidedBy: string | null
  voidReason: string | null
}

type BoardRow = { id: string, guild_id: string, current_round: number, status: 'active' | 'closed' }
type ItemRow = { id: string, item_id: number | null, item_name: string, icon_key: string, copies: number, note: string }
type CandidateRow = { id: string, item_id: string, player_id: string, priority: number, status: LootCandidateStatus }
type AwardRow = {
  id: string, item_id: string, player_id: string, round_number: number,
  priority_snapshot: number, manual_override: boolean, override_reason: string | null,
  awarded_by: string, awarded_at: string, voided_at: string | null,
  voided_by: string | null, void_reason: string | null
}
type PlayerRow = { id: string, name: string, class_id: ClassId, spec_id: string, role: Role }

function normalizePriorityGroups(priorities: number[]): number[] {
  const rankMap = new Map<number, number>()
  return priorities.map(priority => {
    if (!rankMap.has(priority)) rankMap.set(priority, rankMap.size + 1)
    return rankMap.get(priority)!
  })
}

export function useLoot() {
  const supabase = useNuxtApp().$supabase
  const { membership, canEdit, user } = useGuild()
  const board = useState<LootBoardRecord | null>('loot:board', () => null)
  const items = useState<LootItemRecord[]>('loot:items', () => [])
  const candidates = useState<LootCandidateRecord[]>('loot:candidates', () => [])
  const awards = useState<LootAwardRecord[]>('loot:awards', () => [])
  const isLoading = useState<boolean>('loot:loading', () => false)
  const isBusy = useState<boolean>('loot:busy', () => false)
  const error = useState<string | null>('loot:error', () => null)
  const loadedGuildId = useState<string | null>('loot:loaded-guild-id', () => null)

  const pendingEligible = computed(() => items.value.some(item =>
    awardCount(item.id) < item.copies && eligibleCandidates(item.id).length > 0
  ))
  const hasWaitingLoot = computed(() => items.value.some(item =>
    awardCount(item.id) < item.copies
    && candidates.value.some(candidate => candidate.itemId === item.id && candidate.status === 'active')
  ))

  function setError(cause: unknown) {
    error.value = cause instanceof Error ? cause.message : 'The loot board request failed.'
  }

  function mapItem(row: ItemRow): LootItemRecord {
    return { id: row.id, itemId: row.item_id, name: row.item_name, iconKey: row.icon_key, copies: row.copies, note: row.note }
  }

  function mapCandidate(row: CandidateRow): LootCandidateRecord {
    return { id: row.id, itemId: row.item_id, playerId: row.player_id, priority: row.priority, status: row.status }
  }

  function mapAward(row: AwardRow): LootAwardRecord {
    return {
      id: row.id, itemId: row.item_id, playerId: row.player_id, round: row.round_number,
      priority: row.priority_snapshot, manualOverride: row.manual_override,
      overrideReason: row.override_reason, awardedBy: row.awarded_by,
      awardedAt: row.awarded_at, voidedAt: row.voided_at,
      voidedBy: row.voided_by, voidReason: row.void_reason
    }
  }

  async function loadBoardData(boardId: string) {
    if (!supabase || !membership.value) return
    const guildId = membership.value.guild.id
    const [boardResult, itemResult, candidateResult, awardResult] = await Promise.all([
      supabase.from('guild_loot_boards')
        .select('id, guild_id, current_round, status')
        .eq('guild_id', guildId).eq('id', boardId).single(),
      supabase.from('loot_items')
        .select('id, item_id, item_name, icon_key, copies, note')
        .eq('guild_id', guildId).eq('board_id', boardId).order('created_at'),
      supabase.from('loot_candidates')
        .select('id, item_id, player_id, priority, status')
        .eq('guild_id', guildId).eq('board_id', boardId).order('priority'),
      supabase.from('loot_awards')
        .select('id, item_id, player_id, round_number, priority_snapshot, manual_override, override_reason, awarded_by, awarded_at, voided_at, voided_by, void_reason')
        .eq('guild_id', guildId).eq('board_id', boardId).order('awarded_at')
    ])
    if (boardResult.error) throw boardResult.error
    if (itemResult.error) throw itemResult.error
    if (candidateResult.error) throw candidateResult.error
    if (awardResult.error) throw awardResult.error

    const row = boardResult.data as unknown as BoardRow
    board.value = { id: row.id, currentRound: row.current_round, status: row.status }
    items.value = ((itemResult.data ?? []) as unknown as ItemRow[]).map(mapItem)
    candidates.value = ((candidateResult.data ?? []) as unknown as CandidateRow[]).map(mapCandidate)
    awards.value = ((awardResult.data ?? []) as unknown as AwardRow[]).map(mapAward)
  }

  async function loadBoard(guildId = membership.value?.guild.id) {
    if (!supabase || !guildId) return
    const { data, error: queryError } = await supabase
      .from('guild_loot_boards')
      .select('id, guild_id, current_round, status')
      .eq('guild_id', guildId)
      .maybeSingle()
    if (queryError) throw queryError

    let boardRow = data as unknown as BoardRow | null
    if (!boardRow && canEdit.value) {
      const { data: createdId, error: createError } = await supabase.rpc('ensure_guild_loot_board', { p_guild_id: guildId })
      if (createError) throw createError
      const { data: created, error: readError } = await supabase
        .from('guild_loot_boards')
        .select('id, guild_id, current_round, status')
        .eq('guild_id', guildId).eq('id', String(createdId)).single()
      if (readError) throw readError
      boardRow = created as unknown as BoardRow
    }

    if (!boardRow) {
      board.value = null
      items.value = []
      candidates.value = []
      awards.value = []
      return
    }
    await loadBoardData(boardRow.id)
  }

  async function initialize(guildId = membership.value?.guild.id, force = false) {
    // The composable's useState survives route changes and HMR. A cached guild
    // marker alone is not enough: always fetch again if the board itself is absent.
    if (!supabase || !guildId || (!force && loadedGuildId.value === guildId && board.value)) return
    isLoading.value = true
    error.value = null
    if (loadedGuildId.value !== guildId) {
      board.value = null
      items.value = []
      candidates.value = []
      awards.value = []
    }
    try {
      await loadBoard(guildId)
      loadedGuildId.value = guildId
    } catch (cause) {
      setError(cause)
    } finally {
      isLoading.value = false
    }
  }

  async function retry() {
    if (!membership.value) return
    isLoading.value = true
    error.value = null
    try {
      await loadBoard(membership.value.guild.id)
      loadedGuildId.value = membership.value.guild.id
    } catch (cause) { setError(cause) } finally { isLoading.value = false }
  }

  async function addItem(input: { itemId: number | null, name: string, iconKey: string, copies: number, note: string }) {
    if (!supabase || !membership.value || !user.value || !board.value || !canEdit.value) return
    isBusy.value = true
    error.value = null
    try {
      const { error: insertError } = await supabase.from('loot_items').insert({
        guild_id: membership.value.guild.id,
        board_id: board.value.id,
        item_id: input.itemId,
        item_name: input.name.trim(),
        icon_key: input.iconKey.trim().toLowerCase() || 'inv_misc_questionmark',
        copies: input.copies,
        note: input.note.trim(),
        created_by: user.value.id
      })
      if (insertError) throw insertError
      await loadBoardData(board.value.id)
    } catch (cause) { setError(cause) } finally { isBusy.value = false }
  }

  async function removeItem(itemId: string) {
    if (!supabase || !membership.value || !board.value || !canEdit.value) return
    isBusy.value = true
    error.value = null
    try {
      const { error: deleteError } = await supabase.from('loot_items').delete()
        .eq('guild_id', membership.value.guild.id).eq('board_id', board.value.id).eq('id', itemId)
      if (deleteError) throw deleteError
      await loadBoardData(board.value.id)
    } catch (cause) { setError(cause) } finally { isBusy.value = false }
  }

  async function renameItem(itemId: string, name: string) {
    if (!supabase || !membership.value || !board.value || !canEdit.value) return
    const trimmedName = name.trim()
    if (!trimmedName) {
      error.value = 'Enter an item name.'
      return
    }
    isBusy.value = true
    error.value = null
    try {
      const { error: updateError } = await supabase.from('loot_items').update({ item_name: trimmedName })
        .eq('guild_id', membership.value.guild.id).eq('board_id', board.value.id).eq('id', itemId)
      if (updateError) throw updateError
      await loadBoardData(board.value.id)
    } catch (cause) { setError(cause) } finally { isBusy.value = false }
  }

  async function addCandidate(itemId: string, playerId: string) {
    if (!supabase || !membership.value || !board.value || !canEdit.value) return
    const priority = Math.max(0, ...candidates.value.filter(candidate => candidate.itemId === itemId).map(candidate => candidate.priority)) + 1
    isBusy.value = true
    error.value = null
    try {
      const { error: insertError } = await supabase.from('loot_candidates').insert({
        guild_id: membership.value.guild.id,
        board_id: board.value.id,
        item_id: itemId,
        player_id: playerId,
        priority,
        status: 'active'
      })
      if (insertError) throw insertError
      await loadBoardData(board.value.id)
    } catch (cause) { setError(cause) } finally { isBusy.value = false }
  }

  async function removeCandidate(itemId: string, playerId: string) {
    if (!supabase || !membership.value || !board.value || !canEdit.value) return
    const remainingOrder = candidatesForItem(itemId)
      .filter(candidate => candidate.playerId !== playerId)
      .map(candidate => candidate.playerId)
    const remainingPriorities = normalizePriorityGroups(candidatesForItem(itemId)
      .filter(candidate => candidate.playerId !== playerId)
      .map(candidate => candidate.priority))
    isBusy.value = true
    error.value = null
    try {
      const { error: deleteError } = await supabase.from('loot_candidates').delete()
        .eq('guild_id', membership.value.guild.id).eq('board_id', board.value.id)
        .eq('item_id', itemId).eq('player_id', playerId)
      if (deleteError) throw deleteError
      const { error: reorderError } = await supabase.rpc('reorder_loot_candidates', {
        p_guild_id: membership.value.guild.id,
        p_item_id: itemId,
        p_player_ids: remainingOrder,
        p_priorities: remainingPriorities
      })
      if (reorderError) throw reorderError
      await loadBoardData(board.value.id)
    } catch (cause) { setError(cause) } finally { isBusy.value = false }
  }

  async function setCandidateStatus(itemId: string, playerId: string, status: LootCandidateStatus) {
    if (!supabase || !membership.value || !board.value || !canEdit.value) return
    isBusy.value = true
    error.value = null
    try {
      const { error: updateError } = await supabase.from('loot_candidates').update({ status })
        .eq('guild_id', membership.value.guild.id).eq('board_id', board.value.id)
        .eq('item_id', itemId).eq('player_id', playerId)
      if (updateError) throw updateError
      await loadBoardData(board.value.id)
    } catch (cause) { setError(cause) } finally { isBusy.value = false }
  }

  async function reorderCandidates(itemId: string, playerIds: string[], priorities: number[]) {
    if (!supabase || !membership.value || !board.value || !canEdit.value) return
    const boardId = board.value.id
    const guildId = membership.value.guild.id
    const oldCandidates = candidates.value
    if (playerIds.length !== priorities.length) {
      error.value = 'Every candidate needs a priority rank.'
      return
    }
    const priorityByPlayer = new Map(playerIds.map((playerId, index) => [playerId, priorities[index]!]))
    candidates.value = oldCandidates.map(candidate => candidate.itemId === itemId
      ? { ...candidate, priority: priorityByPlayer.get(candidate.playerId) ?? candidate.priority }
      : candidate)
    isBusy.value = true
    error.value = null
    try {
      // Persist the ordered candidate IDs and priority groups atomically.
      for (const [index, playerId] of playerIds.entries()) {
        if (!playerId || !Number.isInteger(priorities[index]) || priorities[index]! < 1) {
          throw new Error('Candidate order contains an invalid priority rank.')
        }
      }
      const { error: rpcError } = await supabase.rpc('reorder_loot_candidates', {
        p_guild_id: guildId,
        p_item_id: itemId,
        p_player_ids: playerIds,
        p_priorities: priorities
      })
      if (rpcError) throw rpcError
      await loadBoardData(boardId)
    } catch (cause) {
      try { await loadBoardData(boardId) } catch { /* retain the original error */ }
      setError(cause)
    } finally { isBusy.value = false }
  }

  async function award(itemId: string, playerId: string, overrideReason?: string) {
    if (!supabase || !membership.value || !board.value || !canEdit.value) return
    isBusy.value = true
    error.value = null
    try {
      const { error: rpcError } = await supabase.rpc('record_loot_award', {
        p_guild_id: membership.value.guild.id,
        p_board_id: board.value.id,
        p_item_id: itemId,
        p_player_id: playerId,
        p_manual_override: Boolean(overrideReason),
        p_override_reason: overrideReason || null
      })
      if (rpcError) throw rpcError
      await loadBoardData(board.value.id)
    } catch (cause) { setError(cause) } finally { isBusy.value = false }
  }

  async function advanceRound() {
    if (!supabase || !membership.value || !board.value || !canEdit.value) return
    isBusy.value = true
    error.value = null
    try {
      const { error: rpcError } = await supabase.rpc('advance_loot_round', {
        p_guild_id: membership.value.guild.id, p_board_id: board.value.id
      })
      if (rpcError) throw rpcError
      await loadBoardData(board.value.id)
    } catch (cause) { setError(cause) } finally { isBusy.value = false }
  }

  async function voidAward(awardId: string, reason: string) {
    if (!supabase || !membership.value || !board.value || !canEdit.value) return
    isBusy.value = true
    error.value = null
    try {
      const { error: rpcError } = await supabase.rpc('void_loot_award', {
        p_guild_id: membership.value.guild.id, p_award_id: awardId, p_reason: reason
      })
      if (rpcError) throw rpcError
      await loadBoardData(board.value.id)
    } catch (cause) { setError(cause) } finally { isBusy.value = false }
  }

  function candidatesForItem(itemId: string) {
    return candidates.value.filter(candidate => candidate.itemId === itemId)
      .sort((a, b) => a.priority - b.priority)
  }

  function eligibleCandidates(itemId: string) {
    const round = board.value?.currentRound
    const received = new Set(awards.value.filter(award => award.round === round && !award.voidedAt).map(award => award.playerId))
    return candidatesForItem(itemId).filter(candidate => candidate.status === 'active' && !received.has(candidate.playerId))
  }

  function awardCount(itemId: string) {
    return awards.value.filter(award => award.itemId === itemId && !award.voidedAt).length
  }

  function awardsForItem(itemId: string) {
    return awards.value.filter(award => award.itemId === itemId)
      .sort((a, b) => b.awardedAt.localeCompare(a.awardedAt))
  }

  return {
    board, items, candidates, awards, isLoading, isBusy, error, pendingEligible, hasWaitingLoot,
    initialize, retry, addItem, removeItem, renameItem, addCandidate, removeCandidate,
    setCandidateStatus, reorderCandidates, award, advanceRound, voidAward,
    candidatesForItem, eligibleCandidates, awardCount, awardsForItem
  }
}
