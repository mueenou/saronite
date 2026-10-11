<script setup lang="ts">
import { encodeBoardForWeakAura, normalizeName, parseWeakAuraLog, type WeakAuraLog } from '~/utils/weakaura'

const loot = useLoot()
const raid = useRaid()
const { membership } = useGuild()
const { items, candidates, awards, board, isBusy } = loot
const { guildPlayers } = raid

const copied = ref(false)
const importText = ref('')
const parseError = ref<string | null>(null)
const imported = ref<string | null>(null)

const missingIds = computed(() => items.value.filter(item => !item.itemId))

async function copyBoard() {
  const text = encodeBoardForWeakAura({
    guildName: membership.value?.guild.name ?? '',
    round: board.value?.currentRound ?? 1,
    items: items.value,
    candidates: candidates.value,
    awards: awards.value,
    players: guildPlayers.value,
    version: Math.floor(Date.now() / 1000)
  })
  await navigator.clipboard.writeText(text)
  copied.value = true
  setTimeout(() => { copied.value = false }, 2000)
}

const log = computed<WeakAuraLog | null>(() => {
  parseError.value = null
  if (!importText.value.trim()) return null
  try { return parseWeakAuraLog(importText.value) } catch (cause) {
    parseError.value = cause instanceof Error ? cause.message : 'Could not read this text.'
    return null
  }
})

type PreviewRow = { label: string, playerName: string, round: number, override: boolean, itemId?: string, playerId?: string, problem?: string }

const preview = computed<PreviewRow[]>(() => {
  if (!log.value) return []
  const planned = new Map<string, number>()
  return log.value.entries.map(entry => {
    const player = guildPlayers.value.find(person => normalizeName(person.name) === normalizeName(entry.name))
    const matches = items.value.filter(item => item.itemId === entry.gameItemId)
    const item = matches.find(match => loot.awardCount(match.id) + (planned.get(match.id) ?? 0) < match.copies)
    const row: PreviewRow = { label: matches[0]?.name ?? `Item ${entry.gameItemId}`, playerName: player?.name ?? entry.name, round: entry.round, override: entry.override }
    if (!matches.length) return { ...row, problem: 'not on the loot board' }
    if (!item) return { ...row, problem: 'all copies already awarded' }
    if (!player) return { ...row, problem: 'name not in the guild roster' }
    if (!candidates.value.some(candidate => candidate.itemId === item.id && candidate.playerId === player.id)) {
      return { ...row, problem: 'player is not on this item\'s priority list' }
    }
    planned.set(item.id, (planned.get(item.id) ?? 0) + 1)
    return { ...row, itemId: item.id, playerId: player.id }
  })
})

const validRows = computed(() => preview.value.filter(row => !row.problem))

const staleWarning = computed(() => {
  if (!log.value?.version) return false
  const changed = awards.value.flatMap(award => [award.awardedAt, award.voidedAt]).filter(Boolean)
    .some(date => new Date(date!).getTime() / 1000 > log.value!.version)
  return changed
})

const roundChange = computed(() => log.value && board.value && log.value.finalRound > board.value.currentRound
  ? log.value.finalRound
  : null)

async function applyImport() {
  if (!log.value || !validRows.value.length && !roundChange.value) return
  const count = validRows.value.length
  const ok = await loot.importWeakAuraAwards(
    validRows.value.map(row => ({ itemId: row.itemId!, playerId: row.playerId!, round: row.round, override: row.override })),
    log.value.finalRound
  )
  if (ok) {
    imported.value = `Imported ${count} award${count === 1 ? '' : 's'}.`
    importText.value = ''
  }
}
</script>

<template>
  <section class="weakaura panel">
    <details>
      <summary>
        <h2>WeakAura (in game)</h2>
        <span class="muted">Send the board to the loot master's WeakAura, and import what was looted in game.</span>
      </summary>

      <div class="wa-grid">
        <div class="wa-block">
          <h3>1. Send the board to the game</h3>
          <p class="muted">
            Copy the board, then in game click <strong>Load</strong> on the Saronite bar and paste it.
            First time? <a href="/weakaura/saronite-loot.lua" target="_blank">Get the WeakAura code</a> and follow the setup notes at the top of the file.
          </p>
          <button type="button" class="primary" :disabled="!items.length" @click="copyBoard">
            {{ copied ? 'Copied' : 'Copy for WeakAura' }}
          </button>
          <p v-if="missingIds.length" class="warning">
            {{ missingIds.length }} item{{ missingIds.length === 1 ? '' : 's' }} without an item ID won't be sent:
            {{ missingIds.map(item => item.name).join(', ') }}
          </p>
        </div>

        <div class="wa-block">
          <h3>2. Import what was looted in game</h3>
          <p class="muted">In game click <strong>Export</strong> on the Saronite bar, copy the text and paste it here.</p>
          <textarea v-model="importText" rows="3" placeholder="SARONITE-LOG:1;…" spellcheck="false" />
          <p v-if="parseError" class="warning">{{ parseError }}</p>
          <p v-if="imported && !importText" class="ok">{{ imported }}</p>

          <template v-if="log">
            <p v-if="staleWarning" class="warning">Awards were changed on the site after this board was sent to the game. Check the list carefully.</p>
            <ul class="preview">
              <li v-for="(row, index) in preview" :key="index" :class="{ skipped: row.problem }">
                <strong>{{ row.label }}</strong> → {{ row.playerName }}
                <small class="muted">R{{ row.round }}<template v-if="row.override"> · override</template></small>
                <small v-if="row.problem" class="warning">skipped: {{ row.problem }}</small>
              </li>
              <li v-if="!preview.length" class="muted">No awards were recorded in game.</li>
            </ul>
            <p v-if="roundChange" class="muted">The board will move to round {{ roundChange }}.</p>
            <button type="button" class="primary" :disabled="isBusy || (!validRows.length && !roundChange)" @click="applyImport">
              Import {{ validRows.length }} award{{ validRows.length === 1 ? '' : 's' }}
            </button>
          </template>
        </div>
      </div>
    </details>
  </section>
</template>

<style scoped>
summary { display: grid; gap: 2px; cursor: pointer; list-style: none; }
summary::-webkit-details-marker { display: none; }
summary h2 { margin: 0; font-size: 1.2rem; }
summary h2::after { content: ' ▸'; color: var(--fog); font-size: .9rem; }
details[open] summary h2::after { content: ' ▾'; }
.wa-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; margin-top: 14px; }
.wa-block { display: grid; align-content: start; gap: 8px; }
.wa-block h3 { margin: 0; font-size: 1.05rem; }
.wa-block p { margin: 0; }
.wa-block button { justify-self: start; }
.wa-block a { color: var(--frost); }
textarea { width: 100%; font-family: monospace; font-size: .8rem; resize: vertical; }
.preview { list-style: none; margin: 0; padding: 0; display: grid; gap: 4px; }
.preview li { display: flex; flex-wrap: wrap; gap: 6px; align-items: baseline; }
.preview li.skipped strong { opacity: .6; }
.warning { color: #f0b06d; }
.ok { color: var(--ok); }
@media (max-width: 720px) { .wa-grid { grid-template-columns: 1fr; } }
</style>
