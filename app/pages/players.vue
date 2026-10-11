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
    <AppHeader />
    <div class="page-title">
      <h1>Guild roster</h1>
      <p class="muted">Players shared by the raid planner and the loot board.</p>
    </div>
    <PublicRosterShare />
    <p v-if="apiStatus === 'offline'" class="connection-warning" role="status">
      Supabase unavailable. You may be seeing cached roster data.
      <button type="button" @click="raid.retryConnection">Retry</button>
    </p>
    <GuildRosterPanel />
  </div>
</template>

<style scoped>
.players-page { max-width: 1480px; margin: 0 auto; padding: 20px clamp(12px, 3vw, 32px) 48px; display: grid; gap: 16px; }
.connecting { min-height: 100vh; display: grid; place-items: center; color: var(--fog); }
.page-title h1 { margin: 0 0 2px; font-size: clamp(1.8rem, 3.5vw, 2.6rem); }
.page-title p { margin: 0; }
.connection-warning { margin: 0; color: #f0b06d; }
</style>
