<script setup lang="ts">
const { bench, byId, unplace, removeCharacter, placeInFirstFree, fillOpenSlots, state, groupCount, selectedId } = useRaid()
const { canEdit } = useGuild()
const hover = ref(false)
const openSlots = computed(() => state.value.groups.slice(0, groupCount.value)
  .reduce((total, group) => total + group.filter(id => id === null).length, 0))

function onDrop(e: DragEvent) {
  hover.value = false
  const id = e.dataTransfer?.getData('text/plain')
  if (id && byId.value.has(id)) unplace(id)
}
</script>

<template>
  <aside
    class="bench panel"
    :class="{ hover }"
    aria-label="Bench"
    @dragover.prevent="hover = true"
    @dragleave.self="hover = false"
    @drop.prevent="onDrop"
  >
    <header>
      <h2>Bench</h2>
      <div class="bench-actions">
        <span class="muted">{{ bench.length }}</span>
        <button
          v-if="canEdit && bench.length"
          class="fill-slots"
          type="button"
          :disabled="openSlots === 0"
          title="Place benched players into the first open raid slots"
          @click="fillOpenSlots"
        >
          Fill slots
        </button>
      </div>
    </header>

    <p v-if="selectedId && !bench.some(c => c.id === selectedId)" class="drop-note">
      <button type="button" @click="unplace(selectedId!)">Move to bench</button>
    </p>

    <ul v-if="bench.length" class="list">
      <li v-for="c in bench" :key="c.id" @dblclick="placeInFirstFree(c.id)">
        <CharacterChip :character="c" removable @remove="removeCharacter(c.id)" />
      </li>
    </ul>
    <p v-else class="muted empty">
      Everyone is in a group. Drag someone here to bench them, or add a character below.
    </p>

    <AddCharacterForm />
  </aside>
</template>

<style scoped>
.bench { display: grid; gap: 12px; align-content: start; transition: box-shadow 120ms; }
.bench.hover { box-shadow: 0 0 0 2px var(--frost); }
header { display: flex; align-items: baseline; justify-content: space-between; }
.bench-actions { display: flex; align-items: center; gap: 8px; }
.fill-slots { padding: 4px 8px; font-size: .82rem; background: var(--ice-ridge); }
.fill-slots:disabled { opacity: .45; cursor: default; }
h2 { font-size: 1.3rem; }
.list { list-style: none; margin: 0; padding: 0; display: grid; gap: 6px; max-height: 50vh; overflow-y: auto; }
.empty { font-size: 0.9rem; margin: 0; }
.drop-note { margin: 0; }
</style>
