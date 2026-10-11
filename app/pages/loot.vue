<script setup lang="ts">
import type { LootItemRecord } from '~/composables/useLoot'
import { CLASS_BY_ID, SPEC_BY_ID } from '~/data/classes'

const guild = useGuild()
const raid = useRaid()
const loot = useLoot()
const { configured, isLoading: guildLoading, user, membership, canEdit } = guild
const { guildPlayers } = raid
const {
  board, items, candidates, awards,
  isLoading, isBusy, error, pendingEligible, hasWaitingLoot
} = loot

const itemName = ref('')
const itemId = ref('')
const iconKey = ref('inv_misc_questionmark')
const copies = ref(1)
const itemNote = ref('')
const selectedPlayers = ref<Record<string, string>>({})
const memberNames = ref<Record<string, string>>({})
const searchQuery = ref('')
const renamingItemId = ref<string | null>(null)
const renameValue = ref('')
const filteredItems = computed(() => {
  const query = searchQuery.value.trim().toLowerCase()
  if (!query) return items.value
  return items.value.filter(item => item.name.toLowerCase().includes(query)
    || (item.itemId !== null && String(item.itemId).includes(query)))
})

onMounted(() => { void guild.initialize() })
watch(() => membership.value?.guild.id, async id => {
  if (!id) return
  await Promise.all([raid.initialize(id, true), loot.initialize(id, true)])
  try {
    const members = await guild.listMembers()
    memberNames.value = Object.fromEntries(members.map(member => [member.user_id, member.profiles?.display_name ?? member.user_id.slice(0, 8)]))
  } catch { /* member names are a display enhancement; the loot board still works without them */ }
}, { immediate: true })

async function createItem() {
  const parsedId = Number(itemId.value)
  await loot.addItem({
    itemId: Number.isInteger(parsedId) && parsedId > 0 ? parsedId : null,
    name: itemName.value,
    iconKey: iconKey.value,
    copies: copies.value,
    note: itemNote.value
  })
  if (!loot.error.value) {
    itemName.value = ''
    itemId.value = ''
    iconKey.value = 'inv_misc_questionmark'
    copies.value = 1
    itemNote.value = ''
  }
}

function beginRename(item: LootItemRecord) {
  renamingItemId.value = item.id
  renameValue.value = item.name
}

async function saveRename(item: LootItemRecord) {
  await loot.renameItem(item.id, renameValue.value)
  if (!loot.error.value) {
    renamingItemId.value = null
    renameValue.value = ''
  }
}

function cancelRename() {
  renamingItemId.value = null
  renameValue.value = ''
}

function candidatesFor(item: LootItemRecord) {
  return loot.candidatesForItem(item.id)
}

function playerName(playerId: string) {
  return guildPlayers.value.find(player => player.id === playerId)?.name ?? playerId
}

function playerClass(playerId: string) {
  const player = guildPlayers.value.find(value => value.id === playerId)
  return player ? CLASS_BY_ID[player.classId].name : 'Unknown class'
}

function playerColor(playerId: string) {
  const player = guildPlayers.value.find(value => value.id === playerId)
  return player ? CLASS_BY_ID[player.classId].color : 'var(--rime)'
}

function memberName(userId: string) {
  return memberNames.value[userId] ?? userId.slice(0, 8)
}

function candidateReceivedThisRound(playerId: string) {
  return awards.value.some(award => award.playerId === playerId && award.round === board.value?.currentRound && !award.voidedAt)
}

function addPlayerToItem(itemId: string) {
  const playerId = selectedPlayers.value[itemId]
  if (!playerId) return
  void loot.addCandidate(itemId, playerId)
  selectedPlayers.value[itemId] = ''
}

function reorderCandidate(itemId: string, index: number, delta: -1 | 1) {
  const ordered = loot.candidatesForItem(itemId)
  const target = index + delta
  if (target < 0 || target >= ordered.length) return
  const ids = ordered.map(candidate => candidate.playerId)
  const priorities = ordered.map(candidate => candidate.priority)
  ;[ids[index], ids[target]] = [ids[target]!, ids[index]!]
  void loot.reorderCandidates(itemId, ids, priorities)
}

function tieCandidateWithPrevious(itemId: string, index: number) {
  if (index < 1) return
  const ordered = loot.candidatesForItem(itemId)
  const priorities = ordered.map(candidate => candidate.priority)
  priorities[index] = priorities[index - 1]!
  const normalized = normalizePriorityGroups(priorities)
  void loot.reorderCandidates(itemId, ordered.map(candidate => candidate.playerId), normalized)
}

function splitCandidateTie(itemId: string, index: number) {
  const ordered = loot.candidatesForItem(itemId)
  const priorities = normalizePriorityGroups(ordered.map(candidate => candidate.priority))
  const rank = priorities[index]
  if (rank === undefined || priorities.filter(priority => priority === rank).length < 2) return

  const firstIndex = priorities.indexOf(rank)
  const splitFrom = index === firstIndex ? index + 1 : index
  for (let position = splitFrom; position < priorities.length; position++) {
    if (priorities[position] === rank) priorities[position] = rank + 1
    else if (priorities[position]! > rank) priorities[position]!++
  }

  void loot.reorderCandidates(
    itemId,
    ordered.map(candidate => candidate.playerId),
    normalizePriorityGroups(priorities)
  )
}

function normalizePriorityGroups(priorities: number[]) {
  const rankMap = new Map<number, number>()
  return priorities.map(priority => {
    if (!rankMap.has(priority)) rankMap.set(priority, rankMap.size + 1)
    return rankMap.get(priority)!
  })
}

function topTieCandidates(itemId: string) {
  const eligible = loot.eligibleCandidates(itemId)
  const topPriority = eligible[0]?.priority
  return topPriority === undefined ? [] : eligible.filter(candidate => candidate.priority === topPriority)
}

function awardTop(item: LootItemRecord) {
  const winner = loot.eligibleCandidates(item.id)[0]
  if (winner) void loot.award(item.id, winner.playerId)
}

function overrideAward(item: LootItemRecord, playerId: string) {
  const reason = window.prompt(`Why is ${playerName(playerId)} receiving ${item.name} outside their normal priority?`)
  if (reason?.trim()) void loot.award(item.id, playerId, reason.trim())
}

function deleteItem(item: LootItemRecord) {
  if (window.confirm(`Remove ${item.name} from the permanent loot board?`)) void loot.removeItem(item.id)
}

function voidAward(awardId: string, item: LootItemRecord) {
  const reason = window.prompt(`Why should the award for ${item.name} be voided?`)
  if (reason?.trim()) void loot.voidAward(awardId, reason.trim())
}

const printSheet = ref<{ exportPdf: () => Promise<void> } | null>(null)
</script>

<template>
  <GuildAccess v-if="!configured || guildLoading || !user || !membership" />
  <main v-else-if="isLoading" class="loading" role="status">Loading the guild loot board…</main>
  <div v-else class="loot-page">
    <header class="loot-header">
      <div>
        <h1>Loot attribution</h1>
        <p class="muted">Round-based priority: a player who wins loot is skipped on other items until the next round.</p>
      </div>
      <GuildTools />
    </header>
    <GuildFeatureNav />

    <section class="board-bar panel">
      <div>
        <h2>Permanent guild loot board</h2>
        <p class="muted">All awards stay in this board's history. Current priority round: {{ board?.currentRound ?? 1 }}</p>
      </div>
      <button v-if="items.length" type="button" @click="printSheet?.exportPdf()">Export PDF</button>
      <button
        v-if="canEdit && board?.status === 'active' && hasWaitingLoot && !pendingEligible"
        type="button"
        :disabled="isBusy"
        @click="loot.advanceRound"
      >
        Start round {{ board.currentRound + 1 }}
      </button>
    </section>

    <p v-if="!canEdit" class="read-only-note">View-only access. Ask a guild officer to add players or change loot priorities.</p>
    <p v-if="error" class="error" role="alert">
      {{ error }}
      <button type="button" @click="loot.retry">Retry</button>
    </p>

    <p v-if="!board" class="panel empty-state">The permanent loot board will appear here when a guild officer opens this page.</p>

    <section v-if="board" class="board-content">
      <div v-if="canEdit && board.status === 'active'" class="add-item panel">
        <h2>Add loot</h2>
        <form @submit.prevent="createItem">
          <label>Item name <input v-model="itemName" maxlength="100" required placeholder="Item name"></label>
          <label>Item ID <input v-model="itemId" type="number" min="1" placeholder="Optional"></label>
          <label>WoW icon key <input v-model="iconKey" maxlength="80" pattern="[a-zA-Z0-9_]+" placeholder="inv_jewelry_trinket_03"></label>
          <label>Copies <input v-model.number="copies" type="number" min="1" max="20" required></label>
          <label class="note-field">Note <input v-model="itemNote" maxlength="500" placeholder="Boss, difficulty, or loot notes"></label>
          <button class="primary" type="submit" :disabled="isBusy || !itemName.trim()">Add item</button>
        </form>
        <p class="muted">Enter the lowercase WoW texture name only—not the item name or ID, and omit <code>.jpg</code>. For example, this item uses <code>inv_jewelry_trinket_03</code>. Item IDs link to the WotLK Wowhead page.</p>
      </div>

      <div v-if="items.length" class="loot-search panel">
        <label for="loot-search">Search items</label>
        <input id="loot-search" v-model="searchQuery" type="search" placeholder="Search by item name or ID…">
        <span class="muted">{{ filteredItems.length }} of {{ items.length }}</span>
      </div>

      <div v-if="!items.length" class="panel empty-state">No loot added to the permanent board yet.</div>
      <div v-else-if="!filteredItems.length" class="panel empty-state">No items match “{{ searchQuery }}”.</div>

      <details v-for="item in filteredItems" :key="item.id" class="loot-item panel">
        <summary class="item-summary">
          <img
            class="item-icon"
            :src="`https://wow.zamimg.com/images/wow/icons/large/${item.iconKey}.jpg`"
            :alt="`${item.name} icon`"
            @error="($event.target as HTMLImageElement).src = 'https://wow.zamimg.com/images/wow/icons/large/inv_misc_questionmark.jpg'"
          >
          <strong class="summary-item-name">{{ item.name }}</strong>
          <span class="summary-next">
            <small>Next eligible</small>
            <strong
              v-if="loot.eligibleCandidates(item.id).length"
              :style="{ color: playerColor(loot.eligibleCandidates(item.id)[0]!.playerId) }"
            >
              {{ playerName(loot.eligibleCandidates(item.id)[0]!.playerId) }}
              <small v-if="topTieCandidates(item.id).length > 1" class="tie-count">+{{ topTieCandidates(item.id).length - 1 }} tied</small>
            </strong>
            <span v-else class="muted">{{ loot.awardCount(item.id) >= item.copies ? 'All copies awarded' : 'None this round' }}</span>
          </span>
        </summary>

        <div class="item-expanded">
          <div class="item-heading">
            <div class="item-meta">
              <a v-if="item.itemId" :href="`https://www.wowhead.com/wotlk/item=${item.itemId}`" target="_blank" rel="noreferrer">View item {{ item.itemId }} on Wowhead</a>
              <span v-else class="muted">No item ID linked</span>
              <small v-if="item.note" class="muted">{{ item.note }}</small>
            </div>
            <span class="copies">{{ loot.awardCount(item.id) }} / {{ item.copies }} awarded</span>
            <form v-if="renamingItemId === item.id" class="rename-form" @submit.prevent="saveRename(item)">
              <input v-model="renameValue" maxlength="100" aria-label="New item name" required>
              <button type="submit" :disabled="isBusy || !renameValue.trim()">Save</button>
              <button type="button" class="quiet" :disabled="isBusy" @click="cancelRename">Cancel</button>
            </form>
            <button v-else-if="canEdit" type="button" class="quiet rename-button" :disabled="isBusy" @click="beginRename(item)">Rename</button>
            <button v-if="canEdit && !loot.awardsForItem(item.id).length" class="quiet remove-item" type="button" @click="deleteItem(item)">Remove item</button>
          </div>

          <div class="priority-area">
            <div class="priority-list">
              <h3>Priority list</h3>
              <ol v-if="candidatesFor(item).length">
                <li v-for="(candidate, index) in candidatesFor(item)" :key="candidate.id" :class="{ passed: candidate.status === 'passed' }">
                  <span class="rank">{{ candidate.priority }}</span>
                  <span class="candidate-name">
                    <strong :style="{ color: playerColor(candidate.playerId) }">{{ playerName(candidate.playerId) }}</strong>
                    <small>{{ playerClass(candidate.playerId) }}</small>
                  </span>
                  <span v-if="candidate.status === 'passed'" class="badge passed-badge">Passed</span>
                  <span v-else-if="candidateReceivedThisRound(candidate.playerId)" class="badge received-badge">Received this round</span>
                  <span v-else-if="candidatesFor(item).filter(other => other.priority === candidate.priority).length > 1" class="badge tie-badge">
                    {{ topTieCandidates(item.id).some(other => other.playerId === candidate.playerId) ? 'Roll tie' : `Tied · priority ${candidate.priority}` }}
                  </span>
                  <span v-else class="badge eligible-badge">{{ loot.eligibleCandidates(item.id)[0]?.playerId === candidate.playerId ? 'Next' : 'Eligible' }}</span>
                  <div v-if="canEdit && board.status === 'active'" class="candidate-actions">
                    <button type="button" :disabled="isBusy || index === 0" aria-label="Move candidate up" @click="reorderCandidate(item.id, index, -1)">↑</button>
                    <button type="button" :disabled="isBusy || index === candidatesFor(item).length - 1" aria-label="Move candidate down" @click="reorderCandidate(item.id, index, 1)">↓</button>
                    <button v-if="index > 0 && candidate.priority !== candidatesFor(item)[index - 1]!.priority" type="button" :disabled="isBusy" title="Tie this player with the priority immediately above" @click="tieCandidateWithPrevious(item.id, index)">Tie</button>
                    <button v-else-if="candidatesFor(item).filter(other => other.priority === candidate.priority).length > 1" type="button" :disabled="isBusy" title="Give this player a separate priority rank" @click="splitCandidateTie(item.id, index)">Split</button>
                    <button v-if="topTieCandidates(item.id).length > 1 && topTieCandidates(item.id).some(other => other.playerId === candidate.playerId) && candidate.status === 'active'" type="button" class="roll-award" :disabled="isBusy" @click="loot.award(item.id, candidate.playerId)">Record roll winner</button>
                    <button v-if="candidate.status === 'active'" type="button" class="quiet" :disabled="isBusy" @click="loot.setCandidateStatus(item.id, candidate.playerId, 'passed')">Pass</button>
                    <button v-else type="button" :disabled="isBusy" @click="loot.setCandidateStatus(item.id, candidate.playerId, 'active')">Restore</button>
                    <button type="button" class="quiet" :disabled="isBusy" aria-label="Remove candidate" @click="loot.removeCandidate(item.id, candidate.playerId)">×</button>
                    <button v-if="candidate.status === 'active' && loot.eligibleCandidates(item.id)[0]?.playerId !== candidate.playerId && loot.awardCount(item.id) < item.copies" type="button" class="override" :disabled="isBusy" @click="overrideAward(item, candidate.playerId)">Override</button>
                  </div>
                </li>
              </ol>
              <p v-else class="muted">No players ranked for this item.</p>

              <form v-if="canEdit && board.status === 'active'" class="add-candidate" @submit.prevent="addPlayerToItem(item.id)">
                <select v-model="selectedPlayers[item.id]" required>
                  <option disabled value="">Add a guild player…</option>
                  <option v-for="player in guildPlayers.filter(person => !candidatesFor(item).some(candidate => candidate.playerId === person.id))" :key="player.id" :value="player.id">
                    {{ player.name }} · {{ CLASS_BY_ID[player.classId].name }}
                  </option>
                </select>
                <button type="submit" :disabled="isBusy || !selectedPlayers[item.id]">Add candidate</button>
              </form>
            </div>

            <aside class="award-panel">
              <h3>Award</h3>
              <p v-if="loot.awardCount(item.id) >= item.copies" class="complete">All copies awarded</p>
              <template v-else-if="loot.eligibleCandidates(item.id).length">
                <p v-if="topTieCandidates(item.id).length > 1">Roll among {{ topTieCandidates(item.id).length }} players tied at priority {{ topTieCandidates(item.id)[0]!.priority }}. Record the winner in the priority list.</p>
                <p v-else>Next eligible: <strong :style="{ color: playerColor(loot.eligibleCandidates(item.id)[0]!.playerId) }">{{ playerName(loot.eligibleCandidates(item.id)[0]!.playerId) }}</strong></p>
                <button v-if="canEdit && board.status === 'active' && topTieCandidates(item.id).length === 1" class="primary" :disabled="isBusy" @click="awardTop(item)">Award to top eligible</button>
              </template>
              <p v-else class="muted">No eligible candidates this round. Advance the round when all remaining items are waiting.</p>

              <details class="award-history">
                <summary>Award history ({{ loot.awardsForItem(item.id).length }})</summary>
                <ol>
                  <li v-for="award in loot.awardsForItem(item.id)" :key="award.id" :class="{ voided: award.voidedAt }">
                    <span>Round {{ award.round }} · <strong :style="{ color: playerColor(award.playerId) }">{{ playerName(award.playerId) }}</strong></span>
                    <small class="muted">Awarded by {{ memberName(award.awardedBy) }} · {{ new Date(award.awardedAt).toLocaleString() }}</small>
                    <span v-if="award.manualOverride" class="muted">Override: {{ award.overrideReason }}</span>
                    <span v-if="award.voidedAt" class="muted">Voided by {{ memberName(award.voidedBy ?? '') }} · {{ new Date(award.voidedAt).toLocaleString() }}: {{ award.voidReason }}</span>
                    <button v-else-if="canEdit" type="button" class="quiet" :disabled="isBusy" @click="voidAward(award.id, item)">Void</button>
                  </li>
                </ol>
              </details>
            </aside>
          </div>
        </div>
      </details>
    </section>
    <LootPrintSheet ref="printSheet" />
  </div>
</template>

<style scoped>
.loot-page { max-width: 1200px; margin: 0 auto; padding: 24px clamp(12px, 3vw, 32px) 48px; display: grid; gap: 16px; }
.loading { min-height: 100vh; display: grid; place-items: center; color: var(--fog); }
.loot-header { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 16px; align-items: start; }
.loot-header h1 { margin: 8px 0 2px; font-size: clamp(1.8rem, 4vw, 2.5rem); }
.loot-header p { margin: 0; }
.board-bar { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 12px; }
.board-bar h2 { font-size: 1.2rem; }
.board-bar p { margin: 2px 0 0; }
.round-chip, .badge { border-radius: 99px; padding: 3px 9px; background: var(--ice-ridge); white-space: nowrap; font-size: .85rem; }
.read-only-note, .error { margin: 0; color: var(--fog); }
.error { color: #ffd1d1; }
.board-content { display: grid; gap: 14px; }
.loot-search { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; }
.loot-search label { color: var(--fog); }
.loot-search input { flex: 1 1 240px; }
.rename-form { display: flex; flex-wrap: wrap; gap: 6px; }
.rename-form input { flex: 1 1 180px; }
.rename-button { justify-self: start; padding: 2px 6px; font-size: .82rem; }
.add-item h2 { margin: 0 0 10px; font-size: 1.2rem; }
.add-item form { display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: 10px; align-items: end; }
.add-item label { display: grid; gap: 4px; color: var(--fog); }
.add-item .note-field { grid-column: span 2; }
.add-item p { margin: 10px 0 0; font-size: .85rem; }
.empty-state { color: var(--fog); }
.loot-item { display: grid; gap: 16px; }
.loot-item:not([open]) { gap: 0; }
.item-summary { display: grid; grid-template-columns: 56px minmax(0, 1fr) minmax(170px, .65fr) 14px; align-items: center; gap: 12px; cursor: pointer; list-style: none; }
.item-summary::-webkit-details-marker { display: none; }
.item-summary::marker { content: ''; }
.item-summary::after { content: '▸'; color: var(--fog); text-align: right; }
.loot-item[open] > .item-summary::after { content: '▾'; }
.summary-item-name { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.summary-next { display: grid; justify-items: end; min-width: 0; text-align: right; }
.summary-next > small { color: var(--fog); font-size: .8rem; }
.summary-next > strong { display: flex; gap: 5px; align-items: baseline; min-width: 0; }
.tie-count { color: var(--fog); font-size: .78rem; font-weight: 400; }
.item-expanded { display: grid; gap: 16px; border-top: 1px solid var(--ice-ridge); padding-top: 14px; }
.item-heading { display: flex; flex-wrap: wrap; align-items: center; gap: 12px; }
.item-meta { display: grid; flex: 1; min-width: 180px; gap: 3px; }
.item-meta a { color: var(--frost); }
.item-icon { width: 48px; height: 48px; border: 1px solid var(--ice-ridge); border-radius: var(--r-sm); background: var(--ice-deep); }
.copies { color: var(--fog); white-space: nowrap; }
.remove-item { align-self: center; }
.priority-area { display: grid; grid-template-columns: minmax(0, 1.5fr) minmax(230px, .8fr); gap: 18px; border-top: 1px solid var(--ice-ridge); padding-top: 14px; }
.priority-area h3 { font-size: 1.05rem; margin: 0 0 8px; }
.priority-list ol, .award-history ol { list-style: none; margin: 0; padding: 0; display: grid; gap: 6px; }
.priority-list li { display: flex; align-items: center; flex-wrap: wrap; gap: 8px; border-bottom: 1px solid rgba(141, 165, 178, .15); padding: 6px 0; }
.priority-list li.passed .candidate-name { opacity: .55; text-decoration: line-through; }
.rank { min-width: 26px; color: var(--fog); text-align: center; }
.candidate-name { display: grid; min-width: 110px; flex: 1; }
.candidate-name small { color: var(--fog); }
.received-badge { background: #58436f; }
.eligible-badge { background: #234a3b; }
.passed-badge { background: #493b3b; }
.candidate-actions { display: flex; flex-wrap: wrap; gap: 4px; }
.candidate-actions button { padding: 3px 7px; }
.candidate-actions .override { background: #745e2f; }
.candidate-actions .roll-award { background: var(--frost); color: var(--ice-deep); font-weight: 700; }
.add-candidate { display: flex; gap: 8px; margin-top: 12px; }
.add-candidate select { flex: 1; }
.award-panel { display: grid; align-content: start; gap: 8px; padding: 12px; background: var(--ice-deep); border-radius: var(--r-sm); }
.award-panel p { margin: 0; }
.complete { color: var(--ok); }
.award-history { margin-top: 8px; }
.award-history summary { color: var(--fog); cursor: pointer; }
.award-history ol { margin-top: 8px; }
.award-history li { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
.award-history li span:first-child { flex: 1; }
.award-history li.voided { opacity: .6; text-decoration: line-through; }
@media (max-width: 720px) {
  .priority-area { grid-template-columns: 1fr; }
  .item-summary { grid-template-columns: 48px minmax(0, 1fr) 14px; gap: 8px; }
  .summary-next { grid-column: 2 / 3; grid-row: 2; justify-items: start; text-align: left; }
  .item-summary::after { grid-column: 3; grid-row: 1 / 3; }
  .copies { flex: 1; }
  .add-item .note-field { grid-column: auto; }
}
</style>
