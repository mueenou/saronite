<script setup lang="ts">
import type { RaidSize } from '#shared/types'

const guild = useGuild()
const raid = useRaid()
const { configured, isLoading: guildLoading, user, membership, canEdit } = guild
const {
  state, groupCount, setSize, sortByRole, clearGroups, loadDemo, startEmpty,
  shareUrl, selectedId, savedRaids, activeRaidId, apiStatus, apiError,
  selectRaid, saveRaid, removeSavedRaid
} = raid

onMounted(() => { void guild.initialize() })
watch(() => membership.value?.guild.id, id => {
  if (id) void raid.initialize(id, true)
}, { immediate: true })

const copied = ref(false)
async function copyShareLink() {
  const url = shareUrl()
  try {
    await navigator.clipboard.writeText(url)
  } catch {
    window.prompt('Copy this link', url)
  }
  copied.value = true
  setTimeout(() => (copied.value = false), 2000)
}

const sizes: RaidSize[] = [10, 25]

function onSavedRaidChange(event: Event) {
  const id = (event.target as HTMLSelectElement).value
  if (id) void selectRaid(id)
}

function deleteCurrentRaid() {
  if (!activeRaidId.value) return
  const raid = savedRaids.value.find(item => item.id === activeRaidId.value)
  if (window.confirm(`Delete “${raid?.title ?? 'this raid'}”? This cannot be undone.`)) {
    void removeSavedRaid(activeRaidId.value)
  }
}

function onKey(e: KeyboardEvent) {
  if (e.key === 'Escape') selectedId.value = null
}
onMounted(() => window.addEventListener('keydown', onKey))
onBeforeUnmount(() => window.removeEventListener('keydown', onKey))
</script>

<template>
  <GuildAccess v-if="!configured || guildLoading || !user || !membership" />
  <main v-else-if="apiStatus === 'loading'" class="connecting" role="status">
    Loading {{ membership.guild.name }}’s raid data…
  </main>
  <div v-else class="page">
    <header class="top">
      <div class="brand">
        <span class="mark" aria-hidden="true">◆</span>
        <span>Saronite</span>
      </div>
      <GuildTools />
      <GuildFeatureNav />

      <div class="title-row">
        <label class="visually-hidden" for="raid-title">Raid name</label>
        <input id="raid-title" v-model="state.title" class="raid-title" maxlength="60" :disabled="!canEdit">
        <div class="size" role="group" aria-label="Raid size">
          <button
            v-for="s in sizes"
            :key="s"
            type="button"
            :aria-pressed="state.size === s"
            :class="{ on: state.size === s }"
            :disabled="!canEdit"
            @click="setSize(s)"
          >
            {{ s }}-player
          </button>
        </div>
      </div>

      <RoleSummary />

      <div class="saved-controls">
        <label for="saved-raids">Saved raids</label>
        <select id="saved-raids" :value="activeRaidId ?? ''" @change="onSavedRaidChange">
          <option value="">Unsaved raid</option>
          <option v-for="raid in savedRaids" :key="raid.id" :value="raid.id">
            {{ raid.title || 'Untitled raid' }}
          </option>
        </select>
        <button v-if="canEdit" type="button" class="primary" :disabled="apiStatus === 'saving'" @click="saveRaid">Save raid</button>
        <button v-if="canEdit" type="button" :disabled="!activeRaidId" @click="deleteCurrentRaid">Delete saved raid</button>
      </div>

      <p class="api-status" :class="`status-${apiStatus}`" role="status">
        <template v-if="apiStatus === 'saving'">Saving raid…</template>
        <template v-else-if="apiStatus === 'offline'">
          Supabase unavailable; changes are cached locally. {{ apiError }}
          <button type="button" @click="raid.retryConnection">Retry</button>
        </template>
        <template v-else>Connected to Supabase · {{ canEdit ? 'raid editing enabled' : 'view only' }}</template>
      </p>

      <nav class="actions" aria-label="Raid actions">
        <button type="button" class="primary" @click="copyShareLink">
          {{ copied ? 'Link copied' : 'Copy share link' }}
        </button>
        <template v-if="canEdit">
          <button type="button" @click="sortByRole">Sort by role</button>
          <button type="button" @click="clearGroups">Clear groups</button>
          <button type="button" class="quiet" @click="loadDemo">Load example raid</button>
          <button type="button" class="quiet" @click="startEmpty">Start empty</button>
        </template>
      </nav>
    </header>

    <p v-if="!canEdit" class="read-only-note">You have view-only access. Ask a guild officer to edit raids or the player roster.</p>

    <p v-if="selectedId" class="picking" role="status">
      Tap a slot to place this character, or press Escape to cancel.
    </p>

    <main class="layout" :inert="!canEdit">
      <BenchPanel class="col-bench" />

      <div class="col-groups">
        <div class="groups" :class="`size-${state.size}`">
          <RaidGroup v-for="g in groupCount" :key="g" :index="g - 1" />
        </div>
        <HintList />
      </div>

      <BuffBoard class="col-board" />
    </main>
  </div>
</template>

<style scoped>
.page { max-width: 1480px; margin: 0 auto; padding: 20px clamp(12px, 3vw, 32px) 48px; }
.connecting { min-height: 100vh; display: grid; place-items: center; color: var(--fog); }

.top { display: grid; gap: 14px; margin-bottom: 20px; }
.brand { display: flex; align-items: center; gap: 8px; color: var(--fog); font-family: var(--font-display); }
.mark { color: var(--saronite); }

.title-row { display: flex; flex-wrap: wrap; align-items: center; gap: 12px 20px; }
.raid-title {
  flex: 1 1 320px;
  font-family: var(--font-display);
  font-size: clamp(1.8rem, 3.5vw, 2.6rem);
  background: transparent;
  border: 0;
  border-bottom: 1px solid transparent;
  border-radius: 0;
  padding: 0;
  color: var(--rime);
}
.raid-title:hover, .raid-title:focus { border-bottom-color: var(--ice-ridge); }

.size { display: inline-flex; border: 1px solid var(--ice-ridge); border-radius: var(--r-sm); overflow: hidden; }
.size button { border-radius: 0; background: transparent; border: 0; color: var(--fog); }
.size button.on { background: var(--ice-ridge); color: var(--frost); }

.actions { display: flex; flex-wrap: wrap; gap: 8px; }
.saved-controls { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
.saved-controls label { color: var(--fog); }
.saved-controls select { min-width: 180px; max-width: 100%; }
.api-status { margin: 0; color: var(--fog); font-size: .9rem; }
.api-status.status-offline { color: #f0b06d; }
.read-only-note { margin: 0 0 14px; color: var(--fog); }

.picking {
  position: sticky; top: 0; z-index: 5;
  margin: 0 0 12px;
  padding: 8px 12px;
  background: var(--saronite);
  color: #fff;
  border-radius: var(--r-sm);
}

.layout {
  display: grid;
  grid-template-columns: 260px minmax(0, 1fr) 340px;
  gap: var(--gap);
  align-items: start;
}
.col-groups { display: grid; gap: var(--gap); }
.groups { display: grid; gap: 12px; grid-template-columns: repeat(auto-fill, minmax(190px, 1fr)); }

@media (max-width: 1180px) {
  .layout { grid-template-columns: 240px minmax(0, 1fr); }
  .col-board { grid-column: 1 / -1; }
}
@media (max-width: 720px) {
  .layout { grid-template-columns: 1fr; }
  .col-groups { order: -1; }
  .groups { grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); }
}
</style>
