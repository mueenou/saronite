<script setup lang="ts">
const guild = useGuild()
const raid = useRaid()
const { configured, isLoading: guildLoading, user, membership } = guild
const { apiStatus } = raid

onMounted(() => { void guild.initialize() })
watch(() => membership.value?.guild.id, id => {
  if (id) void raid.initialize(id, true)
}, { immediate: true })
</script>

<template>
  <GuildAccess v-if="!configured || guildLoading || !user || !membership" />
  <main v-else-if="apiStatus === 'loading'" class="connecting" role="status">Loading {{ membership.guild.name }}’s roster…</main>
  <div v-else class="players-page">
    <header class="page-header">
      <div class="brand"><span class="mark" aria-hidden="true">◆</span><span>Saronite</span></div>
      <GuildTools />
    </header>
    <GuildFeatureNav />
    <PublicRosterShare />
    <p v-if="apiStatus === 'offline'" class="connection-warning" role="status">
      Supabase unavailable. You may be seeing cached roster data.
      <button type="button" @click="raid.retryConnection">Retry</button>
    </p>
    <GuildRosterPanel />
  </div>
</template>

<style scoped>
.players-page { max-width: 1280px; margin: 0 auto; padding: 20px clamp(12px, 3vw, 32px) 48px; display: grid; gap: 16px; }
.connecting { min-height: 100vh; display: grid; place-items: center; color: var(--fog); }
.page-header { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 14px; }
.brand { display: flex; align-items: center; gap: 8px; color: var(--fog); font-family: var(--font-display); }
.mark { color: var(--saronite); }
.connection-warning { margin: 0; color: #f0b06d; }
</style>
