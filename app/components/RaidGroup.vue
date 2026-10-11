<script setup lang="ts">
const props = defineProps<{ index: number }>()
const { state, byId, selectedId, place } = useRaid()

const slots = computed(() => state.value.groups[props.index]!)
const hoverSlot = ref<number | null>(null)

function onDrop(e: DragEvent, slot: number) {
  hoverSlot.value = null
  const id = e.dataTransfer?.getData('text/plain')
  if (id && byId.value.has(id)) place(id, props.index, slot)
}

/** With a character picked, tapping any slot (empty or occupied) places or swaps it */
function onSlotClick(e: MouseEvent, slot: number) {
  const picked = selectedId.value
  if (!picked || slots.value[slot] === picked) return
  e.stopPropagation()
  place(picked, props.index, slot)
}
</script>

<template>
  <section class="group panel" :aria-label="`Group ${index + 1}`">
    <h3>Group {{ index + 1 }}</h3>
    <ol class="slots">
      <li
        v-for="(id, slot) in slots"
        :key="slot"
        class="slot"
        :class="{ hover: hoverSlot === slot, armed: !!selectedId }"
        @dragover.prevent="hoverSlot = slot"
        @dragleave="hoverSlot = null"
        @drop.prevent="onDrop($event, slot)"
        @click.capture="onSlotClick($event, slot)"
      >
        <CharacterChip v-if="id && byId.get(id)" :character="byId.get(id)!" />
        <button v-else type="button" class="empty" :disabled="!selectedId">
          {{ selectedId ? 'Place here' : 'Empty' }}
        </button>
      </li>
    </ol>
  </section>
</template>

<style scoped>
.group { padding: 12px; }
h3 { font-size: 1.05rem; margin-bottom: 8px; color: var(--frost); }
.slots { list-style: none; margin: 0; padding: 0; display: grid; gap: 6px; }
.slot { border-radius: var(--r-sm); transition: box-shadow 120ms; }
.slot.hover { box-shadow: 0 0 0 2px var(--frost); }
.empty {
  width: 100%;
  min-height: 44px;
  background: transparent;
  border: 1px dashed var(--ice-ridge);
  color: var(--fog);
  font-size: 0.85rem;
}
.empty:disabled { cursor: default; }
.slot.armed .empty { border-color: var(--saronite); color: var(--rime); }
</style>
