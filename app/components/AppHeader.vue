<template>
  <header class="app-header">
    <div class="app-header-row">
      <div class="brand"><span class="mark" aria-hidden="true">◆</span><span>Saronite</span></div>
      <GuildTools />
    </div>
    <GuildFeatureNav />
  </header>
</template>

<style scoped>
.app-header { display: grid; gap: 12px; }
.app-header-row { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 14px; }
.brand { display: flex; align-items: center; gap: 8px; color: var(--fog); font-family: var(--font-display); }
.mark { color: var(--saronite); }
</style>
