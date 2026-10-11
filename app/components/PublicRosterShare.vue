<script setup lang="ts">
const supabase = useNuxtApp().$supabase
const { membership, canEdit } = useGuild()

const shareUrl = ref('')
const isBusy = ref(false)
const error = ref<string | null>(null)
const message = ref<string | null>(null)

async function createOrRotateLink() {
  if (!supabase || !membership.value || !canEdit.value) return
  isBusy.value = true
  error.value = null
  message.value = null
  try {
    const { data, error: rpcError } = await supabase.rpc('create_guild_public_share', {
      p_guild_id: membership.value.guild.id
    })
    if (rpcError) throw rpcError
    shareUrl.value = new URL(`/share/${encodeURIComponent(String(data))}`, window.location.origin).toString()
    message.value = 'Public read-only link created. Creating another link will invalidate the previous one.'
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'Could not create the public link.'
  } finally {
    isBusy.value = false
  }
}

async function revokeLink() {
  if (!supabase || !membership.value || !canEdit.value) return
  if (!window.confirm('Disable the current public roster and loot link? Anyone using it will lose access.')) return
  isBusy.value = true
  error.value = null
  message.value = null
  try {
    const { error: rpcError } = await supabase.rpc('revoke_guild_public_share', {
      p_guild_id: membership.value.guild.id
    })
    if (rpcError) throw rpcError
    shareUrl.value = ''
    message.value = 'The current public link has been disabled.'
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'Could not disable the public link.'
  } finally {
    isBusy.value = false
  }
}

async function copyLink() {
  try {
    await navigator.clipboard.writeText(shareUrl.value)
    message.value = 'Public link copied.'
  } catch {
    window.prompt('Copy this public read-only link', shareUrl.value)
  }
}
</script>

<template>
  <section v-if="canEdit" class="public-share panel">
    <div class="share-heading">
      <div>
        <h2>Public read-only link</h2>
        <p class="muted">Anyone with the link can view the guild roster and loot priorities/history without an account.</p>
      </div>
      <div class="share-actions">
        <button class="primary" type="button" :disabled="isBusy" @click="createOrRotateLink">
          {{ isBusy ? 'Please wait…' : shareUrl ? 'Rotate link' : 'Create link' }}
        </button>
        <button v-if="shareUrl" type="button" :disabled="isBusy" @click="revokeLink">Revoke link</button>
      </div>
    </div>
    <div v-if="shareUrl" class="share-url-row">
      <input :value="shareUrl" readonly aria-label="Public read-only link">
      <button type="button" @click="copyLink">Copy link</button>
    </div>
    <p v-if="message" class="share-message" role="status">{{ message }}</p>
    <p v-if="error" class="share-error" role="alert">{{ error }}</p>
  </section>
</template>

<style scoped>
.public-share { display: grid; gap: 12px; }
.share-heading { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 14px; }
.share-heading h2 { margin: 0; font-size: 1.2rem; }
.share-heading p { margin: 4px 0 0; }
.share-actions, .share-url-row { display: flex; flex-wrap: wrap; gap: 8px; }
.share-url-row input { flex: 1 1 320px; }
.share-message, .share-error { margin: 0; }
.share-message { color: var(--ok); }
.share-error { color: #ffd1d1; }
</style>
