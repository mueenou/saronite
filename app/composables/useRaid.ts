import type { Character, ClassId, GuildPlayer, RaidSize, RaidState, Role, SavedRaid } from '#shared/types'
import { demoRaid, emptyRaid } from '~/data/demo'
import { SPEC_BY_ID } from '~/data/classes'

const CACHE_PREFIX = 'saronite:raid:v3:'
export type RaidApiStatus = 'loading' | 'online' | 'saving' | 'offline'
type CachedRaid = { id: string | null, state: RaidState }
type RaidRow = {
  id: string
  guild_id: string
  title: string
  size: RaidSize
  state: RaidState
  created_at: string
  updated_at: string
}
type PlayerRow = {
  id: string
  name: string
  class_id: ClassId
  spec_id: string
  role: Role
}

let saveTimer: ReturnType<typeof setTimeout> | undefined
let saveQueue: Promise<void> = Promise.resolve()

function isRaidState(value: unknown): value is RaidState {
  if (!value || typeof value !== 'object') return false
  const raid = value as Partial<RaidState>
  return typeof raid.title === 'string'
    && (raid.size === 10 || raid.size === 25)
    && Array.isArray(raid.roster)
    && Array.isArray(raid.groups)
}

function newRaidId(): string {
  return globalThis.crypto?.randomUUID?.()
    ?? `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`.replace(/[xy]/g, char => {
      const random = Math.random() * 16 | 0
      return (char === 'x' ? random : (random & 0x3 | 0x8)).toString(16)
    })
}

function toSavedRaid(row: RaidRow): SavedRaid {
  return {
    ...row.state,
    title: row.title,
    size: row.size,
    id: row.id,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  }
}

function toGuildPlayer(row: PlayerRow): GuildPlayer {
  return { id: row.id, name: row.name, classId: row.class_id, specId: row.spec_id, role: row.role }
}

function readCache(guildId: string): CachedRaid | null {
  try {
    const cached = JSON.parse(localStorage.getItem(`${CACHE_PREFIX}${guildId}`) ?? 'null') as Partial<CachedRaid> | null
    if (cached && isRaidState(cached.state)) {
      return { id: typeof cached.id === 'string' ? cached.id : null, state: cached.state }
    }
  } catch { /* unavailable or invalid local cache */ }
  return null
}

function loadInitial(): RaidState {
  if (import.meta.client) {
    const shared = new URL(window.location.href).searchParams.get('raid')
    if (shared) {
      const decoded = decodeRaid(shared)
      if (decoded) return decoded
    }
  }
  return emptyRaid()
}

export function useRaid() {
  const state = useState<RaidState>('raid', loadInitial)
  const selectedId = useState<string | null>('raid:selected', () => null)
  const savedRaids = useState<SavedRaid[]>('raid:saved', () => [])
  const guildPlayers = useState<GuildPlayer[]>('guild:players', () => [])
  const activeRaidId = useState<string | null>('raid:active-id', () => null)
  const apiStatus = useState<RaidApiStatus>('raid:api-status', () => 'loading')
  const apiError = useState<string | null>('raid:api-error', () => null)
  const hydrating = useState<boolean>('raid:hydrating', () => false)
  const loadedGuildId = useState<string | null>('raid:loaded-guild-id', () => null)
  const editedDuringLoad = useState<boolean>('raid:edited-during-load', () => false)
  const watcherInstalled = useState<boolean>('raid:persistence-watcher-installed', () => false)
  const supabase = useNuxtApp().$supabase
  const { membership, canEdit, user } = useGuild()

  function cacheCurrentRaid() {
    const guildId = membership.value?.guild.id
    if (!guildId || !import.meta.client) return
    try {
      localStorage.setItem(`${CACHE_PREFIX}${guildId}`, JSON.stringify({ id: activeRaidId.value, state: state.value } satisfies CachedRaid))
    } catch { /* storage unavailable or full */ }
  }

  function handleError(error: unknown) {
    apiStatus.value = 'offline'
    apiError.value = error instanceof Error ? error.message : 'Supabase request failed.'
  }

  async function fetchGuildPlayers(guildId: string) {
    if (!supabase) return
    const { data, error } = await supabase
      .from('guild_players')
      .select('id, name, class_id, spec_id, role')
      .eq('guild_id', guildId)
      .order('name')
    if (error) throw error
    guildPlayers.value = ((data ?? []) as unknown as PlayerRow[]).map(toGuildPlayer)
  }

  async function loadForGuild(guildId = membership.value?.guild.id, force = false) {
    if (!supabase || !guildId || (!force && loadedGuildId.value === guildId)) return
    const sharedCode = import.meta.client ? new URL(window.location.href).searchParams.get('raid') : null
    const hasSharedRaid = Boolean(sharedCode && decodeRaid(sharedCode))
    if (loadedGuildId.value !== guildId) {
      hydrating.value = true
      savedRaids.value = []
      guildPlayers.value = []
      activeRaidId.value = null
      if (!hasSharedRaid) state.value = emptyRaid()
      editedDuringLoad.value = false
      hydrating.value = false
    }
    apiStatus.value = 'loading'
    apiError.value = null

    try {
      const [raidResult, playerResult] = await Promise.all([
        supabase.from('raids')
          .select('id, guild_id, title, size, state, created_at, updated_at')
          .eq('guild_id', guildId)
          .order('updated_at', { ascending: false }),
        supabase.from('guild_players')
          .select('id, name, class_id, spec_id, role')
          .eq('guild_id', guildId)
          .order('name')
      ])
      if (raidResult.error) throw raidResult.error
      if (playerResult.error) throw playerResult.error

      const raids = ((raidResult.data ?? []) as unknown as RaidRow[]).map(toSavedRaid)
      savedRaids.value = raids
      guildPlayers.value = ((playerResult.data ?? []) as unknown as PlayerRow[]).map(toGuildPlayer)

      if (!hasSharedRaid && !editedDuringLoad.value) {
        const cached = import.meta.client ? readCache(guildId) : null
        const selected = raids.find(raid => raid.id === cached?.id) ?? (!cached ? raids[0] : undefined)
        hydrating.value = true
        if (selected) {
          activeRaidId.value = selected.id
          state.value = toRaidState(selected)
        } else if (cached) {
          activeRaidId.value = cached.id
          state.value = cached.state
        } else {
          activeRaidId.value = null
          state.value = emptyRaid()
        }
        hydrating.value = false
      }
      apiStatus.value = 'online'
      loadedGuildId.value = guildId
    } catch (error) {
      handleError(error)
      if (!hasSharedRaid && !editedDuringLoad.value) {
        const cached = import.meta.client ? readCache(guildId) : null
        hydrating.value = true
        if (cached) {
          activeRaidId.value = cached.id
          state.value = cached.state
        } else {
          activeRaidId.value = null
          state.value = emptyRaid()
        }
        hydrating.value = false
      }
    } finally {
      cacheCurrentRaid()
    }
  }

  async function persistActiveRaid(): Promise<void> {
    const guildId = membership.value?.guild.id
    if (!supabase || !guildId || !activeRaidId.value || !canEdit.value) return
    const id = activeRaidId.value
    const snapshot = JSON.parse(JSON.stringify(state.value)) as typeof state.value
    apiStatus.value = 'saving'
    apiError.value = null

    const operation = saveQueue.catch(() => undefined).then(async () => {
      const { error } = await supabase.rpc('save_raid', {
        p_guild_id: guildId,
        p_raid_id: id,
        p_state: snapshot
      })
      if (error) throw error
      const { data, error: queryError } = await supabase
        .from('raids')
        .select('id, guild_id, title, size, state, created_at, updated_at')
        .eq('guild_id', guildId)
        .eq('id', id)
        .single()
      if (queryError) throw queryError
      const saved = toSavedRaid(data as unknown as RaidRow)
      const exists = savedRaids.value.some(raid => raid.id === id)
      savedRaids.value = exists
        ? savedRaids.value.map(raid => raid.id === id ? saved : raid)
        : [saved, ...savedRaids.value]
      await fetchGuildPlayers(guildId)
      if (activeRaidId.value === id) {
        apiStatus.value = 'online'
        cacheCurrentRaid()
      }
    })
    saveQueue = operation.catch(handleError)
    await saveQueue
  }

  function scheduleSave() {
    if (!activeRaidId.value || !canEdit.value) return
    if (saveTimer) clearTimeout(saveTimer)
    saveTimer = setTimeout(() => {
      saveTimer = undefined
      void persistActiveRaid()
    }, 500)
  }

  async function flushPendingSave() {
    if (saveTimer) {
      clearTimeout(saveTimer)
      saveTimer = undefined
      await persistActiveRaid()
    } else {
      await saveQueue
    }
  }

  if (!watcherInstalled.value) {
    watcherInstalled.value = true
    watch(state, () => {
      if (hydrating.value || !import.meta.client) return
      if (apiStatus.value === 'loading') editedDuringLoad.value = true
      cacheCurrentRaid()
      scheduleSave()
    }, { deep: true, flush: 'sync' })
    onScopeDispose(() => { watcherInstalled.value = false })
  }

  const groupCount = computed(() => visibleGroupCount(state.value))
  const coverage = computed(() => computeCoverage(state.value))
  const hints = computed(() => computeHints(state.value, coverage.value))
  const placed = computed(() => placedCharacters(state.value))
  const placedIds = computed(() => new Set(placed.value.map(p => p.character.id)))
  const bench = computed(() => state.value.roster.filter(c => !placedIds.value.has(c.id)))
  const byId = computed(() => new Map(state.value.roster.map(c => [c.id, c])))

  function findSlot(id: string): [number, number] | null {
    for (let group = 0; group < state.value.groups.length; group++) {
      const slot = state.value.groups[group]!.indexOf(id)
      if (slot !== -1) return [group, slot]
    }
    return null
  }

  function place(id: string, group: number, slot: number) {
    const groups = state.value.groups
    const from = findSlot(id)
    const occupant = groups[group]![slot] ?? null
    if (from) groups[from[0]]![from[1]] = occupant
    groups[group]![slot] = id
    selectedId.value = null
  }

  function unplace(id: string) {
    const from = findSlot(id)
    if (from) state.value.groups[from[0]]![from[1]] = null
    selectedId.value = null
  }

  function placeInFirstFree(id: string) {
    for (let group = 0; group < groupCount.value; group++) {
      const slot = state.value.groups[group]!.indexOf(null)
      if (slot !== -1) return place(id, group, slot)
    }
  }

  /** Fill visible raid slots in current bench order; leave overflow benched. */
  function fillOpenSlots() {
    const ids = bench.value.map(character => character.id)
    let count = 0
    for (const id of ids) {
      let targetGroup = -1
      let targetSlot = -1
      for (let group = 0; group < groupCount.value; group++) {
        const slot = state.value.groups[group]!.indexOf(null)
        if (slot !== -1) {
          targetGroup = group
          targetSlot = slot
          break
        }
      }
      if (targetGroup < 0) break
      place(id, targetGroup, targetSlot)
      count++
    }
    return count
  }

  function addCharacter(input: { name: string, classId: ClassId, specId: string, role: Role }) {
    const base = input.name.trim().toLowerCase().replace(/[^a-z0-9]/g, '') || 'player'
    let id = base
    let suffix = 2
    while (byId.value.has(id) || guildPlayers.value.some(player => player.id === id)) id = `${base}${suffix++}`
    const character: Character = { id, name: input.name.trim(), classId: input.classId, specId: input.specId, role: input.role }
    state.value.roster.push(character)
    return character
  }

  function addGuildPlayer(id: string) {
    const player = guildPlayers.value.find(item => item.id === id)
    if (!player || byId.value.has(id)) return
    state.value.roster.push({ ...player })
  }

  async function createGuildPlayer(input: { id?: string, name: string, classId: ClassId, specId: string, role: Role }): Promise<boolean> {
    if (!supabase || !membership.value || !user.value || !canEdit.value) return false
    const base = input.name.trim().toLowerCase().replace(/[^a-z0-9]/g, '') || 'player'
    let id = input.id ?? base
    let suffix = 2
    while (guildPlayers.value.some(player => player.id === id)) {
      if (input.id) {
        apiError.value = `${input.name} is already in the guild roster.`
        return false
      }
      id = `${base}${suffix++}`
    }

    apiStatus.value = 'saving'
    apiError.value = null
    try {
      const { data, error } = await supabase.from('guild_players').insert({
        guild_id: membership.value.guild.id,
        id,
        name: input.name.trim(),
        class_id: input.classId,
        spec_id: input.specId,
        role: input.role,
        created_by: user.value.id
      }).select('id, name, class_id, spec_id, role').single()
      if (error) throw error

      const player = toGuildPlayer(data as unknown as PlayerRow)
      guildPlayers.value = [...guildPlayers.value, player].sort((a, b) => a.name.localeCompare(b.name))
      apiStatus.value = 'online'
      return true
    } catch (error) {
      handleError(error)
      return false
    }
  }

  function removeCharacter(id: string) {
    unplace(id)
    state.value.roster = state.value.roster.filter(character => character.id !== id)
  }

  function cycleRole(id: string) {
    const character = byId.value.get(id)
    if (!character) return
    const roles = SPEC_BY_ID[character.specId]!.roles
    character.role = roles[(roles.indexOf(character.role) + 1) % roles.length]!
  }

  function setSize(size: RaidSize) { state.value.size = size }

  function sortByRole() {
    const order: Role[] = ['tank', 'melee', 'ranged', 'healer']
    const ids = placed.value
      .map(item => item.character)
      .sort((a, b) => order.indexOf(a.role) - order.indexOf(b.role) || a.classId.localeCompare(b.classId))
      .map(character => character.id)
    const groups = Array.from({ length: 5 }, () => Array<string | null>(5).fill(null))
    ids.forEach((id, index) => { groups[Math.floor(index / 5)]![index % 5] = id })
    state.value.groups = groups
  }

  function clearGroups() { state.value.groups = Array.from({ length: 5 }, () => Array(5).fill(null)) }

  async function loadDemo() {
    await flushPendingSave()
    hydrating.value = true
    activeRaidId.value = null
    state.value = demoRaid()
    selectedId.value = null
    hydrating.value = false
    cacheCurrentRaid()
  }

  async function startEmpty() {
    await flushPendingSave()
    hydrating.value = true
    activeRaidId.value = null
    state.value = emptyRaid()
    selectedId.value = null
    hydrating.value = false
    cacheCurrentRaid()
  }

  async function selectRaid(id: string) {
    const raid = savedRaids.value.find(item => item.id === id)
    if (!raid) return
    await flushPendingSave()
    hydrating.value = true
    activeRaidId.value = raid.id
    state.value = toRaidState(raid)
    selectedId.value = null
    hydrating.value = false
    cacheCurrentRaid()
  }

  async function saveRaid() {
    if (!supabase || !membership.value || !canEdit.value) return
    const id = activeRaidId.value ?? newRaidId()
    activeRaidId.value = id
    cacheCurrentRaid()
    await persistActiveRaid()
  }

  async function retryConnection() {
    if (activeRaidId.value && canEdit.value) {
      await persistActiveRaid()
      return
    }
    loadedGuildId.value = null
    await loadForGuild()
  }

  async function removeSavedRaid(id: string) {
    const guildId = membership.value?.guild.id
    if (!supabase || !guildId || !canEdit.value) return
    if (id === activeRaidId.value && saveTimer) {
      clearTimeout(saveTimer)
      saveTimer = undefined
    }
    try {
      await saveQueue
      const { error } = await supabase.from('raids').delete().eq('guild_id', guildId).eq('id', id)
      if (error) throw error
      savedRaids.value = savedRaids.value.filter(raid => raid.id !== id)
      if (activeRaidId.value === id) {
        const next = savedRaids.value[0]
        hydrating.value = true
        activeRaidId.value = next?.id ?? null
        state.value = next ? toRaidState(next) : emptyRaid()
        selectedId.value = null
        hydrating.value = false
      }
      apiStatus.value = 'online'
      apiError.value = null
      cacheCurrentRaid()
    } catch (error) {
      handleError(error)
    }
  }

  function shareUrl(): string {
    const url = new URL(window.location.href)
    url.search = ''
    url.searchParams.set('raid', encodeRaid(state.value))
    return url.toString()
  }

  function toggleSelect(id: string) { selectedId.value = selectedId.value === id ? null : id }

  return {
    state, selectedId, groupCount, coverage, hints, placed, bench, byId,
    savedRaids, guildPlayers, activeRaidId, apiStatus, apiError,
    place, unplace, placeInFirstFree, fillOpenSlots, addCharacter, addGuildPlayer, createGuildPlayer,
    removeCharacter, cycleRole, setSize, sortByRole, clearGroups,
    loadDemo, startEmpty, selectRaid, saveRaid, removeSavedRaid,
    initialize: loadForGuild, retryConnection, shareUrl, toggleSelect
  }
}

function toRaidState(raid: SavedRaid): RaidState {
  const { id: _id, createdAt: _createdAt, updatedAt: _updatedAt, ...state } = raid
  return state
}
