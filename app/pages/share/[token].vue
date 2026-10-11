<script setup lang="ts">
import type { RaidState, Role } from '#shared/types'
import { CLASS_BY_ID, ROLE_LABEL, ROLE_TARGETS, SPEC_BY_ID } from '~/data/classes'
import { visibleGroupCount } from '~/utils/coverage'

type PublicPlayer = { id: string, name: string, classId: keyof typeof CLASS_BY_ID, specId: string, role: string }
type PublicCandidate = { playerId: string, priority: number, status: 'active' | 'passed' }
type PublicAward = {
  playerId: string
  round: number
  priority: number
  manualOverride: boolean
  overrideReason: string | null
  awardedAt: string
  voidedAt: string | null
  voidReason: string | null
}
type PublicItem = {
  id: string
  itemId: number | null
  name: string
  iconKey: string
  copies: number
  note: string
  candidates: PublicCandidate[]
  awards: PublicAward[]
}
type PublicGuildView = {
  guild: { name: string }
  currentRound: number
  raids: PublicRaid[]
  players: PublicPlayer[]
  items: PublicItem[]
}
type PublicRaid = { id: string, title: string, state: RaidState, updatedAt: string }

const route = useRoute()
const supabase = useNuxtApp().$supabase
const data = ref<PublicGuildView | null>(null)
const isLoading = ref(true)
const error = ref<string | null>(null)
const tab = ref<'roster' | 'loot'>('roster')
const raidId = ref<string | null>(null)

const activeRaid = computed(() => {
  const raids = data.value?.raids ?? []
  return raids.find(raid => raid.id === raidId.value) ?? raids[0] ?? null
})
const characterById = computed(() => new Map((activeRaid.value?.state.roster ?? []).map(character => [character.id, character])))
const visibleGroups = computed(() => activeRaid.value
  ? activeRaid.value.state.groups.slice(0, visibleGroupCount(activeRaid.value.state))
  : [])
const placedIds = computed(() => new Set(visibleGroups.value.flat().filter((id): id is string => !!id && characterById.value.has(id))))
const placedCount = computed(() => placedIds.value.size)
const benchCharacters = computed(() => (activeRaid.value?.state.roster ?? []).filter(character => !placedIds.value.has(character.id)))
const roleRows = computed(() => (['tank', 'healer', 'melee', 'ranged'] as Role[]).map(role => {
  const size = activeRaid.value?.state.size ?? 25
  const count = [...placedIds.value].filter(id => characterById.value.get(id)?.role === role).length
  const [min, max] = ROLE_TARGETS[size][role]
  return { role, count, min, max, status: count < min ? 'low' : count > max ? 'high' : 'ok' }
}))

function playerName(playerId: string) {
  return data.value?.players.find(player => player.id === playerId)?.name ?? playerId
}

function playerColor(playerId: string) {
  const player = data.value?.players.find(entry => entry.id === playerId)
  return player ? CLASS_BY_ID[player.classId]?.color ?? 'var(--rime)' : 'var(--rime)'
}

function eligibleCandidates(item: PublicItem) {
  const receivedThisRound = new Set((data.value?.items ?? []).flatMap(entry => entry.awards)
    .filter(award => award.round === data.value?.currentRound && !award.voidedAt)
    .map(award => award.playerId))
  return item.candidates
    .filter(candidate => candidate.status === 'active' && !receivedThisRound.has(candidate.playerId))
    .sort((a, b) => a.priority - b.priority)
}

function awardCount(item: PublicItem) {
  return item.awards.filter(award => !award.voidedAt).length
}

function topEligibleCandidates(item: PublicItem) {
  const eligible = eligibleCandidates(item)
  const priority = eligible[0]?.priority
  return priority === undefined ? [] : eligible.filter(candidate => candidate.priority === priority)
}

onMounted(async () => {
  if (!supabase) {
    error.value = 'The public view is not configured.'
    isLoading.value = false
    return
  }

  try {
    const token = Array.isArray(route.params.token) ? route.params.token[0] : route.params.token
    const { data: result, error: rpcError } = await supabase.rpc('get_public_guild_view', { p_token: token })
    if (rpcError) throw rpcError
    if (!result) throw new Error('This public link is invalid or has been revoked.')
    data.value = { ...(result as PublicGuildView), raids: (result as PublicGuildView).raids ?? [] }
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'Could not load this public guild view.'
  } finally {
    isLoading.value = false
  }
})
</script>

<template>
  <main class="public-page">
    <header class="public-header">
      <div class="brand"><span class="mark" aria-hidden="true">◆</span><span>Saronite</span></div>
      <span class="read-only">Public · Read only</span>
    </header>

    <p v-if="isLoading" class="state-message" role="status">Loading shared guild data…</p>
    <section v-else-if="error" class="state-message panel" role="alert">
      <h1>Link unavailable</h1>
      <p>{{ error }}</p>
    </section>

    <template v-else-if="data">
      <nav class="public-tabs" aria-label="Shared guild data">
        <button type="button" :class="{ active: tab === 'roster' }" @click="tab = 'roster'">
          Guild roster ({{ data.players.length }})
        </button>
        <button type="button" :class="{ active: tab === 'loot' }" @click="tab = 'loot'">
          Loot attribution ({{ data.items.length }})
        </button>
      </nav>

      <div class="guild-title">
        <h1>{{ data.guild.name }}</h1>
        <p class="muted">Shared roster and loot priorities</p>
      </div>

      <section v-if="tab === 'roster' && activeRaid" class="public-raid">
        <div class="raid-heading">
          <h2>{{ activeRaid.state.title || activeRaid.title || 'Untitled raid' }}</h2>
          <span class="size-tag">{{ activeRaid.state.size }}-player</span>
        </div>
        <ul class="roles" aria-label="Role balance">
          <li v-for="row in roleRows" :key="row.role" :class="row.status">
            <RoleIcon :role="row.role" />
            <span class="count">{{ row.count }}</span>
            <span class="label">{{ ROLE_LABEL[row.role] }}</span>
            <span class="target muted">{{ row.min === row.max ? row.min : `${row.min}–${row.max}` }}</span>
          </li>
          <li class="total"><span class="count">{{ placedCount }}</span><span class="label">of {{ activeRaid.state.size }}</span></li>
        </ul>
        <div v-if="data.raids.length > 1" class="raid-picker">
          <label for="public-raid">Saved raids</label>
          <select id="public-raid" v-model="raidId">
            <option v-for="raid in data.raids" :key="raid.id" :value="raid.id">{{ raid.state.title || raid.title || 'Untitled raid' }}</option>
          </select>
        </div>

        <div class="raid-layout">
          <section class="panel bench">
            <h3>Bench <span class="muted">{{ benchCharacters.length }}</span></h3>
            <p v-if="!benchCharacters.length" class="muted">Everyone is in a group.</p>
            <ul class="slots">
              <li v-for="character in benchCharacters" :key="character.id"><div class="chip" :style="{ '--class-color': CLASS_BY_ID[character.classId]?.color }"><span class="chip-main"><span class="name">{{ character.name }}</span><span class="spec">{{ SPEC_BY_ID[character.specId]?.name }} {{ CLASS_BY_ID[character.classId]?.name }}</span></span><span class="chip-role"><RoleIcon :role="character.role" /></span></div></li>
            </ul>
          </section>
          <div class="groups">
            <section v-for="(group, groupIndex) in visibleGroups" :key="groupIndex" class="panel group">
              <h3>Group {{ groupIndex + 1 }}</h3>
              <ol class="slots">
                <li v-for="(id, slot) in group" :key="slot">
                  <div v-if="id && characterById.get(id)" class="chip" :style="{ '--class-color': CLASS_BY_ID[characterById.get(id)!.classId]?.color }">
                    <span class="chip-main">
                      <span class="name">{{ characterById.get(id)!.name }}</span>
                      <span class="spec">{{ SPEC_BY_ID[characterById.get(id)!.specId]?.name }} {{ CLASS_BY_ID[characterById.get(id)!.classId]?.name }}</span>
                    </span>
                    <span class="chip-role"><RoleIcon :role="characterById.get(id)!.role" /></span>
                  </div>
                  <div v-else class="empty-slot">Empty</div>
                </li>
              </ol>
            </section>
          </div>
        </div>
      </section>

      <section v-else-if="tab === 'roster'" class="public-roster panel">
        <h2>Guild player roster</h2>
        <p class="muted">No raid has been saved yet.</p>
        <p v-if="!data.players.length" class="muted">The guild roster is empty.</p>
        <ul v-else class="player-grid">
          <li v-for="player in data.players" :key="player.id" :style="{ '--class-color': playerColor(player.id) }">
            <strong>{{ player.name }}</strong>
            <span>{{ CLASS_BY_ID[player.classId]?.name ?? player.classId }} · {{ SPEC_BY_ID[player.specId]?.name ?? player.specId }}</span>
            <small>{{ player.role }}</small>
          </li>
        </ul>
      </section>

      <section v-else class="public-loot">
        <div class="round-label">Priority round {{ data.currentRound }} · read only</div>
        <p v-if="!data.items.length" class="panel muted">No items are on the loot board yet.</p>
        <div v-if="data.items.length" class="public-table-wrap panel">
          <table class="loot-table">
            <thead>
              <tr>
                <th scope="col">Item</th>
                <th scope="col">Next eligible</th>
                <th scope="col">Priority list</th>
                <th scope="col">Awarded</th>
                <th scope="col">History</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="item in data.items" :key="item.id">
                <td>
                  <div class="table-item">
                    <img :src="`https://wow.zamimg.com/images/wow/icons/large/${item.iconKey}.jpg`" :alt="`${item.name} icon`" @error="($event.target as HTMLImageElement).src = 'https://wow.zamimg.com/images/wow/icons/large/inv_misc_questionmark.jpg'">
                    <div>
                      <a v-if="item.itemId" :href="`https://www.wowhead.com/wotlk/item=${item.itemId}`" target="_blank" rel="noreferrer">{{ item.name }}</a>
                      <strong v-else>{{ item.name }}</strong>
                      <small v-if="item.note" class="muted">{{ item.note }}</small>
                    </div>
                  </div>
                </td>
                <td>
                  <template v-if="topEligibleCandidates(item).length">
                    <strong :style="{ color: playerColor(topEligibleCandidates(item)[0]!.playerId) }">{{ playerName(topEligibleCandidates(item)[0]!.playerId) }}</strong>
                    <small v-if="topEligibleCandidates(item).length > 1" class="muted"> · roll tie ({{ topEligibleCandidates(item).length }})</small>
                  </template>
                  <span v-else class="muted">{{ awardCount(item) >= item.copies ? 'Complete' : 'None this round' }}</span>
                </td>
                <td>
                  <ol class="priority-list">
                    <li v-for="candidate in [...item.candidates].sort((a, b) => a.priority - b.priority)" :key="candidate.playerId" :class="{ passed: candidate.status === 'passed' }">
                      <span class="rank">{{ candidate.priority }}</span>
                      <strong :class="{ tied: item.candidates.filter(other => other.priority === candidate.priority).length > 1 }" :style="{ color: playerColor(candidate.playerId) }">{{ playerName(candidate.playerId) }}</strong>
                      <small v-if="candidate.status === 'passed'" class="muted">Passed</small>
                      <small v-else-if="data.items.flatMap(entry => entry.awards).some(award => award.playerId === candidate.playerId && award.round === data.currentRound && !award.voidedAt)" class="muted">Received</small>
                    </li>
                    <li v-if="!item.candidates.length" class="muted">—</li>
                  </ol>
                </td>
                <td class="award-count">{{ awardCount(item) }} / {{ item.copies }}</td>
                <td>
                  <details class="public-history">
                    <summary>{{ item.awards.length }}</summary>
                    <ol class="history-list">
                      <li v-for="(award, index) in item.awards" :key="`${item.id}-${index}`" :class="{ voided: award.voidedAt }">
                        <span>R{{ award.round }} · <strong :style="{ color: playerColor(award.playerId) }">{{ playerName(award.playerId) }}</strong></span>
                        <small v-if="award.manualOverride" class="muted">Override: {{ award.overrideReason }}</small>
                        <small v-if="award.voidedAt" class="muted">Voided: {{ award.voidReason }}</small>
                      </li>
                    </ol>
                  </details>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>
  </main>
</template>

<style scoped>
.public-page { max-width: 1480px; margin: 0 auto; padding: 20px clamp(12px, 3vw, 32px) 48px; display: grid; gap: 16px; }
.public-header { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 14px; margin-bottom: -4px; }
.brand { display: flex; align-items: center; gap: 8px; color: var(--fog); font-family: var(--font-display); }
.mark { color: var(--saronite); }
.read-only, .round-label { color: var(--fog); font-size: .9rem; }
.guild-title h1 { margin: 0 0 2px; font-size: clamp(1.8rem, 3.5vw, 2.6rem); }
.guild-title p { margin: 0; }
.public-raid { display: grid; gap: 14px; }
.raid-heading { display: flex; flex-wrap: wrap; align-items: baseline; gap: 12px; }
.raid-heading h2 { margin: 0; font-size: 1.5rem; }
.size-tag { color: var(--fog); }
.roles { list-style: none; margin: 0; padding: 0; display: flex; flex-wrap: wrap; gap: 8px 20px; }
.roles li { display: flex; align-items: center; gap: 6px; }
.roles .count { font-family: var(--font-display); font-size: 1.5rem; line-height: 1; }
.roles .label { color: var(--fog); }
.roles .target { font-size: .8rem; }
.roles .low .count { color: var(--missing); }
.roles .high .count { color: var(--partial); }
.roles .total { margin-left: auto; }
.raid-picker { display: flex; align-items: center; gap: 10px; color: var(--fog); }
.raid-layout { display: grid; grid-template-columns: 240px minmax(0, 1fr); gap: 16px; align-items: start; }
.groups { display: grid; gap: 12px; grid-template-columns: repeat(auto-fill, minmax(190px, 1fr)); }
.group, .bench { padding: 12px; }
.group h3, .bench h3 { font-size: 1.05rem; margin: 0 0 8px; color: var(--frost); display: flex; justify-content: space-between; }
.slots { list-style: none; margin: 0; padding: 0; display: grid; gap: 6px; }
.chip { display: flex; align-items: stretch; min-height: 44px; background: var(--ice-deep); border-left: 4px solid var(--class-color); border-radius: var(--r-sm); }
.chip-main { flex: 1; min-width: 0; display: flex; flex-direction: column; justify-content: center; padding: 4px 8px; }
.chip .name { color: var(--class-color); font-weight: 700; line-height: 1.15; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.chip .spec { font-size: .8rem; color: var(--fog); line-height: 1.15; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.chip-role { display: grid; place-items: center; padding: 0 8px; color: var(--fog); }
.empty-slot { min-height: 44px; display: grid; place-items: center; border: 1px dashed var(--ice-ridge); border-radius: var(--r-sm); color: var(--fog); font-size: .85rem; }
@media (max-width: 720px) {
  .raid-layout { grid-template-columns: 1fr; }
  .groups { order: -1; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); }
}
.public-tabs { display: flex; flex-wrap: wrap; gap: 6px; border-bottom: 1px solid var(--ice-ridge); padding-bottom: 8px; }
.public-tabs button { padding: 5px 11px; border-radius: var(--r-sm); background: transparent; color: var(--fog); }
.public-tabs button:hover { color: var(--rime); background: var(--ice-ridge); }
.public-tabs button.active { background: var(--frost); color: var(--ice-deep); font-weight: 700; }
.public-roster { display: grid; gap: 12px; }
.public-roster h2, .public-item h3 { margin: 0; font-size: 1.2rem; }
.public-roster p { margin: 0; }
.player-grid { list-style: none; display: grid; grid-template-columns: repeat(auto-fill, minmax(170px, 1fr)); gap: 10px; margin: 0; padding: 0; }
.player-grid li { display: grid; gap: 3px; padding: 11px 13px; background: var(--ice-deep); border-left: 3px solid var(--class-color); border-radius: var(--r-sm); }
.player-grid strong { color: var(--class-color); }
.player-grid span, .player-grid small { color: var(--fog); }
.public-loot { display: grid; gap: 12px; }
.public-table-wrap { max-width: 100%; overflow-x: auto; padding: 0; }
.loot-table { width: 100%; min-width: 760px; border-collapse: collapse; text-align: left; font-size: .9rem; }
.loot-table th, .loot-table td { padding: 8px 10px; border-bottom: 1px solid var(--ice-ridge); vertical-align: middle; }
.loot-table th { background: var(--ice-shelf); color: var(--fog); font-weight: 500; white-space: nowrap; }
.loot-table tbody tr:nth-child(even) { background: rgba(168, 216, 234, .03); }
.loot-table tbody tr:last-child td { border-bottom: 0; }
.table-item { display: flex; align-items: center; gap: 8px; min-width: 190px; }
.table-item img { width: 32px; height: 32px; flex: 0 0 32px; border: 1px solid var(--ice-ridge); border-radius: var(--r-sm); }
.table-item > div { display: grid; min-width: 0; }
.table-item a { color: var(--frost); font-weight: 700; }
.award-count { color: var(--fog); white-space: nowrap; }
.priority-list { list-style: none; display: flex; flex-wrap: wrap; gap: 4px 14px; margin: 0; padding: 0; }
.priority-list li { display: flex; align-items: baseline; gap: 4px; white-space: nowrap; }
.priority-list li.passed strong { opacity: .55; text-decoration: line-through; }
.priority-list strong.tied { position: relative; }
.priority-list strong.tied::after { content: 'roll'; position: absolute; left: 50%; top: 100%; transform: translateX(-50%); color: var(--fog); font-size: .68rem; font-weight: 400; line-height: 1; }
.rank { color: var(--rime); font-size: .9rem; font-weight: 700; }
.rank::after { content: '.'; }
.history-list { list-style: none; display: grid; gap: 5px; min-width: 200px; margin: 6px 0 0; padding: 0; }
.history-list li { display: grid; gap: 2px; }
.history-list li.voided { opacity: .6; text-decoration: line-through; }
.public-history summary { color: var(--frost); cursor: pointer; }
.state-message { max-width: 620px; margin: 12vh auto 0; text-align: center; }
.state-message h1 { margin-bottom: 8px; }
.state-message p { margin: 0; }
</style>
