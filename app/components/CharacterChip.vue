<script setup lang="ts">
import type { Character } from '#shared/types'
import { CLASS_BY_ID, SPEC_BY_ID } from '~/data/classes'

const props = defineProps<{ character: Character, removable?: boolean }>()
const emit = defineEmits<{ remove: [] }>()
const { selectedId, toggleSelect, cycleRole } = useRaid()

const cls = computed(() => CLASS_BY_ID[props.character.classId])
const spec = computed(() => SPEC_BY_ID[props.character.specId])
const isHybrid = computed(() => (spec.value?.roles.length ?? 0) > 1)
const selected = computed(() => selectedId.value === props.character.id)

function onDragStart(e: DragEvent) {
  e.dataTransfer?.setData('text/plain', props.character.id)
  if (e.dataTransfer) e.dataTransfer.effectAllowed = 'move'
}
</script>

<template>
  <div
    class="chip"
    :class="{ selected }"
    :style="{ '--class-color': cls.color }"
    draggable="true"
    @dragstart="onDragStart"
  >
    <button
      class="chip-main"
      type="button"
      :aria-pressed="selected"
      :title="selected ? 'Picked: tap a slot to place' : 'Pick to move'"
      @click.stop="toggleSelect(character.id)"
    >
      <span class="name">{{ character.name }}</span>
      <span class="spec">{{ spec?.name }} {{ cls.name }}</span>
    </button>
    <button
      class="role"
      type="button"
      :class="character.role"
      :disabled="!isHybrid"
      :title="isHybrid ? 'Switch role' : character.role"
      @click.stop="cycleRole(character.id)"
    >
      <RoleIcon :role="character.role" />
      <span class="visually-hidden">{{ character.role }}</span>
    </button>
    <button
      v-if="removable"
      class="remove quiet"
      type="button"
      title="Remove from roster"
      @click.stop="emit('remove')"
    >
      ×
    </button>
  </div>
</template>

<style scoped>
.chip {
  display: flex;
  align-items: stretch;
  background: var(--ice-deep);
  border-left: 4px solid var(--class-color);
  border-radius: var(--r-sm);
  min-height: 44px;
  cursor: grab;
}
.chip.selected {
  outline: 2px solid var(--saronite);
  outline-offset: 1px;
}
.chip-main {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  justify-content: center;
  background: none;
  border: 0;
  padding: 4px 8px;
  text-align: left;
}
.name {
  color: var(--class-color);
  font-weight: 700;
  line-height: 1.15;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.spec {
  font-size: 0.8rem;
  color: var(--fog);
  line-height: 1.15;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 100%;
}
.role {
  background: none;
  border: 0;
  padding: 0 8px;
  display: grid;
  place-items: center;
  color: var(--fog);
}
.role:disabled { cursor: default; opacity: 0.8; }
.role:not(:disabled):hover { color: var(--frost); }
.remove { padding: 0 10px; font-size: 1.1rem; border: 0; }
</style>
