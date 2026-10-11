<script setup lang="ts">
import type { ClassId, Role } from '#shared/types'
import { CLASS_BY_ID, CLASSES, SPEC_BY_ID } from '~/data/classes'

const guild = useGuild()
const raid = useRaid()
const { canEdit, membership } = guild
const { guildPlayers, state, apiStatus, apiError, createGuildPlayer } = raid

const newPlayerName = ref('')
const newPlayerClass = ref<ClassId>('warrior')
const newPlayerSpec = ref('warrior.fury')
const newPlayerRole = ref<Role>('melee')
const selectedRaidRosterPlayer = ref('')
const newPlayerSpecs = computed(() => CLASS_BY_ID[newPlayerClass.value].specs)
const newPlayerRoles = computed(() => SPEC_BY_ID[newPlayerSpec.value]?.roles ?? [])
const raidRosterPlayers = computed(() => state.value.roster.filter(character =>
  !guildPlayers.value.some(player => player.id === character.id)
))

watch(newPlayerClass, () => { newPlayerSpec.value = newPlayerSpecs.value[0]!.id })
watch(newPlayerSpec, () => { newPlayerRole.value = newPlayerRoles.value[0]! })

async function addPlayer() {
  const saved = await createGuildPlayer({
    name: newPlayerName.value,
    classId: newPlayerClass.value,
    specId: newPlayerSpec.value,
    role: newPlayerRole.value
  })
  if (saved) newPlayerName.value = ''
}

async function importRaidRosterPlayer() {
  const character = raidRosterPlayers.value.find(player => player.id === selectedRaidRosterPlayer.value)
  if (!character) return
  const saved = await createGuildPlayer({ ...character })
  if (saved) selectedRaidRosterPlayer.value = ''
}
</script>

<template>
  <section class="guild-roster panel">
    <header class="roster-heading">
      <div>
        <h1>Guild player roster</h1>
        <p class="muted">Manage players used by raid planning and loot priorities. Players don’t need Saronite accounts.</p>
      </div>
      <span class="count-chip">{{ guildPlayers.length }} players</span>
    </header>

    <p v-if="apiStatus === 'offline'" class="error" role="alert">
      Could not sync the roster: {{ apiError }}
      <button type="button" @click="raid.initialize(membership?.guild.id, true)">Retry</button>
    </p>

    <div class="roster-management">
      <div v-if="canEdit" class="roster-add-panel">
        <h2>Add players</h2>
        <p class="muted">Enter a player once, then reuse them in any raid and on the loot board.</p>

        <form class="add-player-form" @submit.prevent="addPlayer">
          <label class="name-field">Player name
            <input v-model="newPlayerName" maxlength="24" placeholder="Player name" required>
          </label>
          <label>Class
            <select v-model="newPlayerClass">
              <option v-for="wowClass in CLASSES" :key="wowClass.id" :value="wowClass.id">{{ wowClass.name }}</option>
            </select>
          </label>
          <label>Specialization
            <select v-model="newPlayerSpec">
              <option v-for="spec in newPlayerSpecs" :key="spec.id" :value="spec.id">{{ spec.name }}</option>
            </select>
          </label>
          <label v-if="newPlayerRoles.length > 1">Role
            <select v-model="newPlayerRole">
              <option v-for="role in newPlayerRoles" :key="role" :value="role">{{ role }}</option>
            </select>
          </label>
          <button class="primary" type="submit" :disabled="apiStatus === 'saving' || !newPlayerName.trim()">
            {{ apiStatus === 'saving' ? 'Saving…' : 'Add player' }}
          </button>
        </form>

        <form v-if="raidRosterPlayers.length" class="import-raid-player" @submit.prevent="importRaidRosterPlayer">
          <label for="raid-roster-player">Or import from a raid</label>
          <select id="raid-roster-player" v-model="selectedRaidRosterPlayer" required>
            <option disabled value="">Select a raid player…</option>
            <option v-for="player in raidRosterPlayers" :key="player.id" :value="player.id">
              {{ player.name }} · {{ CLASS_BY_ID[player.classId].name }} · {{ SPEC_BY_ID[player.specId]?.name ?? player.specId }}
            </option>
          </select>
          <button type="submit" :disabled="apiStatus === 'saving' || !selectedRaidRosterPlayer">Import player</button>
        </form>
      </div>

      <div class="roster-list-panel">
        <h2>Players</h2>
        <p v-if="!guildPlayers.length" class="muted empty-roster">No players added yet.</p>
        <ul v-else class="roster-list">
          <li v-for="player in guildPlayers" :key="player.id" :style="{ '--class-color': CLASS_BY_ID[player.classId].color }">
            <strong>{{ player.name }}</strong>
            <span>{{ CLASS_BY_ID[player.classId].name }} · {{ SPEC_BY_ID[player.specId]?.name ?? player.specId }}</span>
            <small>{{ player.role }}</small>
          </li>
        </ul>
      </div>
    </div>
  </section>
</template>

<style scoped>
.guild-roster { display: grid; gap: 18px; }
.roster-heading { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 12px; }
.roster-heading h1 { font-size: clamp(1.5rem, 3vw, 2rem); }
.roster-heading p { margin: 4px 0 0; }
.count-chip { border-radius: 99px; padding: 4px 10px; background: var(--ice-ridge); white-space: nowrap; color: var(--fog); }
.roster-management { display: grid; grid-template-columns: minmax(260px, .75fr) minmax(0, 1.5fr); align-items: start; gap: 18px; }
.roster-add-panel, .roster-list-panel { min-width: 0; padding: 16px; background: var(--ice-deep); border-radius: var(--r-sm); }
.roster-add-panel h2, .roster-list-panel h2 { margin: 0 0 4px; font-size: 1.15rem; }
.roster-add-panel > p { margin: 0 0 14px; }
.add-player-form { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; align-items: end; }
.add-player-form label { display: grid; gap: 4px; color: var(--fog); font-size: .9rem; }
.add-player-form .name-field, .add-player-form button { grid-column: 1 / -1; }
.add-player-form button { justify-self: start; }
.import-raid-player { display: grid; gap: 8px; margin-top: 18px; padding-top: 16px; border-top: 1px solid var(--ice-ridge); }
.import-raid-player label { color: var(--fog); font-size: .9rem; }
.import-raid-player button { justify-self: start; }
.roster-list { list-style: none; display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 10px; margin: 12px 0 0; padding: 0; }
.roster-list li { display: grid; gap: 3px; min-width: 0; padding: 11px 13px; background: var(--ice-shelf); border-left: 3px solid var(--class-color); border-radius: var(--r-sm); }
.roster-list li strong { color: var(--class-color); }
.roster-list li span, .roster-list li small, .empty-roster { color: var(--fog); }
.empty-roster { margin: 12px 0 0; }
.error { margin: 0; color: #ffd1d1; }
@media (max-width: 760px) { .roster-management { grid-template-columns: 1fr; } }
</style>
