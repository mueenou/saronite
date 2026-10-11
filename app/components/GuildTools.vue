<script setup lang="ts">
import type { GuildRole } from '#shared/types'

const {
  membership, user, isOwnerOrAdmin, canManageInvites,
  createInvite, listMembers, updateMemberRole, refreshMembership, signOut
} = useGuild()

const inviteRole = ref<'member' | 'officer'>('member')
const inviteCode = ref('')
const members = ref<{ user_id: string, role: GuildRole, joined_at: string, profiles: { display_name: string } | null }[]>([])
const busy = ref(false)
const notice = ref('')

async function refreshMembers() {
  try { members.value = await listMembers() } catch (error) {
    notice.value = error instanceof Error ? error.message : 'Could not load guild members.'
  }
}

watch(() => membership.value?.guild.id, id => { if (id) void refreshMembers() }, { immediate: true })

async function generateInvite() {
  busy.value = true
  notice.value = ''
  try {
    inviteCode.value = await createInvite(inviteRole.value)
    await refreshMembers()
  } catch (error) {
    notice.value = error instanceof Error ? error.message : 'Could not create an invite.'
  } finally {
    busy.value = false
  }
}

async function copyInvite() {
  try {
    await navigator.clipboard.writeText(inviteCode.value)
    notice.value = 'Invite code copied.'
  } catch {
    window.prompt('Copy this invite code', inviteCode.value)
  }
}

async function changeRole(memberId: string, event: Event) {
  const role = (event.target as HTMLSelectElement).value as 'admin' | 'officer' | 'member'
  busy.value = true
  notice.value = ''
  try {
    await updateMemberRole(memberId, role)
    if (memberId === user.value?.id) await refreshMembership()
    await refreshMembers()
  } catch (error) {
    notice.value = error instanceof Error ? error.message : 'Could not update member role.'
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <details class="guild-tools">
    <summary>
      {{ membership?.guild.name }} · {{ membership?.role }}
      <span v-if="membership?.guild.discordServerId" class="muted">· Discord linked</span>
    </summary>
    <div class="tools-content">
      <p>Signed in as {{ user?.email }}. Guild members can view raids; officers can edit them.</p>

      <form v-if="canManageInvites" class="invite-form" @submit.prevent="generateInvite">
        <label for="invite-role">Invite as</label>
        <select id="invite-role" v-model="inviteRole">
          <option value="member">Member (view only)</option>
          <option v-if="isOwnerOrAdmin" value="officer">Officer (can edit)</option>
        </select>
        <button type="submit" :disabled="busy">Generate invite code</button>
      </form>

      <div v-if="inviteCode" class="invite-code">
        <code>{{ inviteCode }}</code>
        <button type="button" @click="copyInvite">Copy</button>
        <small>Share this code with your guild member. It expires in 7 days or after 20 uses.</small>
      </div>

      <details v-if="isOwnerOrAdmin" class="member-list">
        <summary>Manage member roles ({{ members.length }})</summary>
        <ul>
          <li v-for="member in members" :key="member.user_id">
            <span>{{ member.profiles?.display_name ?? 'Guild member' }} <code>{{ member.user_id }}</code></span>
            <span v-if="member.role === 'owner'">Owner</span>
            <select v-else :value="member.role" :disabled="busy" @change="changeRole(member.user_id, $event)">
              <option value="member">Member</option>
              <option value="officer">Officer</option>
              <option value="admin">Admin</option>
            </select>
          </li>
        </ul>
      </details>

      <p v-if="notice" role="status">{{ notice }}</p>
      <button class="quiet" type="button" @click="signOut">Sign out</button>
    </div>
  </details>
</template>

<style scoped>
.guild-tools { color: var(--fog); }
.guild-tools > summary, .member-list > summary { cursor: pointer; }
.tools-content { display: grid; gap: 10px; margin-top: 10px; padding: 14px; background: var(--ice-deep); border-radius: var(--r-sm); }
.tools-content p { margin: 0; }
.invite-form { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
.invite-code { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
.invite-code code { overflow-wrap: anywhere; }
.invite-code small { flex-basis: 100%; }
.member-list ul { list-style: none; padding: 0; display: grid; gap: 6px; }
.member-list li { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 8px; }
.member-list code { overflow-wrap: anywhere; }
</style>
