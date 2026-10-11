<script setup lang="ts">
const route = useRoute()

const tabs = [
  { label: 'Raid planner', to: '/' },
  { label: 'Loot attribution', to: '/loot' },
  { label: 'Guild roster', to: '/players' }
]
</script>

<template>
  <nav class="feature-tabs" aria-label="Guild tools">
    <NuxtLink
      v-for="tab in tabs"
      :key="tab.to"
      :to="tab.to"
      :aria-current="route.path === tab.to ? 'page' : undefined"
      :class="{ active: route.path === tab.to }"
    >
      {{ tab.label }}
    </NuxtLink>
  </nav>
</template>

<style scoped>
.feature-tabs { display: flex; flex-wrap: wrap; gap: 6px; border-bottom: 1px solid var(--ice-ridge); padding-bottom: 8px; }
.feature-tabs a { padding: 5px 11px; border-radius: var(--r-sm); color: var(--fog); text-decoration: none; }
.feature-tabs a:hover { color: var(--rime); background: var(--ice-ridge); }
.feature-tabs a.active { color: var(--ice-deep); background: var(--frost); font-weight: 700; }
</style>
