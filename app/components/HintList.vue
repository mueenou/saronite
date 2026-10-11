<script setup lang="ts">
const { hints } = useRaid()
</script>

<template>
  <section v-if="hints.length" class="hints panel" aria-label="Suggestions">
    <h2>Suggestions</h2>
    <ul>
      <li v-for="h in hints" :key="h.id" :class="h.tone">{{ h.text }}</li>
    </ul>
  </section>
</template>

<style scoped>
.hints { display: grid; gap: 8px; }
h2 { font-size: 1.3rem; }
ul { margin: 0; padding: 0; list-style: none; display: grid; gap: 8px; }
li { padding-left: 12px; border-left: 3px solid var(--fog); font-size: 0.95rem; max-width: 75ch; }
li.warn { border-color: var(--partial); }
</style>
