<script setup lang="ts">
import type { ClassId, Role } from '#shared/types'
import { CLASSES, CLASS_BY_ID, SPEC_BY_ID } from '~/data/classes'

const { addCharacter, addGuildPlayer, guildPlayers, state } = useRaid()

const name = ref('')
const classId = ref<ClassId>('warrior')
const specId = ref('warrior.fury')
const role = ref<Role>('melee')
const selectedGuildPlayer = ref('')

const specs = computed(() => CLASS_BY_ID[classId.value].specs)
const roles = computed(() => SPEC_BY_ID[specId.value]?.roles ?? [])
const reusablePlayers = computed(() => guildPlayers.value.filter(player => !state.value.roster.some(character => character.id === player.id)))

watch(classId, () => { specId.value = specs.value[0]!.id })
watch(specId, () => { role.value = roles.value[0]! })

function submit() {
  if (!name.value.trim()) return
  addCharacter({ name: name.value, classId: classId.value, specId: specId.value, role: role.value })
  name.value = ''
}

function addExistingPlayer() {
  if (!selectedGuildPlayer.value) return
  addGuildPlayer(selectedGuildPlayer.value)
  selectedGuildPlayer.value = ''
}
</script>

<template>
  <div class="add">
    <form v-if="reusablePlayers.length" class="existing" @submit.prevent="addExistingPlayer">
      <label for="existing-player">Add from guild roster</label>
      <div class="row">
        <select id="existing-player" v-model="selectedGuildPlayer" required>
          <option disabled value="">Choose a saved player…</option>
          <option v-for="player in reusablePlayers" :key="player.id" :value="player.id">
            {{ player.name }} · {{ CLASS_BY_ID[player.classId].name }}
          </option>
        </select>
        <button type="submit" :disabled="!selectedGuildPlayer">Add</button>
      </div>
    </form>

    <form class="new-player" @submit.prevent="submit">
      <p v-if="reusablePlayers.length" class="muted">Or create a new player</p>
    <label class="visually-hidden" for="char-name">Character name</label>
    <input id="char-name" v-model="name" placeholder="Character name" maxlength="12" autocomplete="off">
    <div class="row">
      <label class="visually-hidden" for="char-class">Class</label>
      <select id="char-class" v-model="classId">
        <option v-for="c in CLASSES" :key="c.id" :value="c.id">{{ c.name }}</option>
      </select>
      <label class="visually-hidden" for="char-spec">Spec</label>
      <select id="char-spec" v-model="specId">
        <option v-for="s in specs" :key="s.id" :value="s.id">{{ s.name }}</option>
      </select>
      <label v-if="roles.length > 1" class="visually-hidden" for="char-role">Role</label>
      <select v-if="roles.length > 1" id="char-role" v-model="role">
        <option v-for="r in roles" :key="r" :value="r">{{ r }}</option>
      </select>
    </div>
    <button class="primary" type="submit" :disabled="!name.trim()">Add to roster</button>
    </form>
  </div>
</template>

<style scoped>
.add, .new-player, .existing { display: grid; gap: 8px; }
.new-player p { margin: 4px 0 0; }
.existing label { color: var(--fog); font-size: .9rem; }
.row { display: flex; gap: 6px; flex-wrap: wrap; }
.row select { flex: 1 1 90px; }
button:disabled { opacity: 0.5; cursor: default; }
</style>
