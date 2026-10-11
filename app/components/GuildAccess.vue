<script setup lang="ts">
const {
  user, membership, isLoading, error, configured,
  signIn, signUp, signOut, createGuild, joinGuild
} = useGuild()

const email = ref('')
const password = ref('')
const displayName = ref('')
const guildName = ref('')
const discordServerId = ref('')
const inviteCode = ref('')
const mode = ref<'sign-in' | 'sign-up'>('sign-in')
const busy = ref(false)
const message = ref<string | null>(null)

async function authenticate() {
  busy.value = true
  message.value = null
  try {
    if (mode.value === 'sign-in') {
      await signIn(email.value.trim(), password.value)
    } else {
      const result = await signUp(email.value.trim(), password.value, displayName.value)
      message.value = result.needsEmailConfirmation
        ? 'Check your email to confirm your account, then sign in.'
        : 'Account created.'
    }
  } catch (cause) {
    message.value = cause instanceof Error ? cause.message : 'Authentication failed.'
  } finally {
    busy.value = false
  }
}

async function createWorkspace() {
  busy.value = true
  message.value = null
  try {
    await createGuild(guildName.value, discordServerId.value.trim())
  } catch (cause) {
    message.value = cause instanceof Error ? cause.message : 'Could not create the guild workspace.'
  } finally {
    busy.value = false
  }
}

async function acceptInvite() {
  busy.value = true
  message.value = null
  try {
    await joinGuild(inviteCode.value)
  } catch (cause) {
    message.value = cause instanceof Error ? cause.message : 'Could not join the guild.'
  } finally {
    busy.value = false
  }
}

async function logOut() {
  try {
    await signOut()
  } catch (cause) {
    message.value = cause instanceof Error ? cause.message : 'Could not sign out.'
  }
}
</script>

<template>
  <main class="access-page">
    <section class="access-card panel">
      <p class="eyebrow">Saronite · Guild workspace</p>
      <h1>Raid planning for your guild</h1>

      <div v-if="!configured" class="notice">
        <h2>Connect Supabase</h2>
        <p>Copy <code>.env.example</code> to <code>.env</code>, add your Supabase project URL and publishable/anon key, then restart Nuxt.</p>
      </div>
      <p v-else-if="isLoading" role="status">Connecting to Supabase…</p>

      <form v-else-if="!user" class="access-form" @submit.prevent="authenticate">
        <h2>{{ mode === 'sign-in' ? 'Sign in' : 'Create an account' }}</h2>
        <template v-if="mode === 'sign-up'">
          <label for="account-name">Display name</label>
          <input id="account-name" v-model="displayName" autocomplete="name" maxlength="60" required>
        </template>
        <label for="account-email">Email</label>
        <input id="account-email" v-model="email" type="email" autocomplete="email" required>
        <label for="account-password">Password</label>
        <input
          id="account-password"
          v-model="password"
          type="password"
          :autocomplete="mode === 'sign-in' ? 'current-password' : 'new-password'"
          minlength="8"
          required
        >
        <button class="primary" type="submit" :disabled="busy">
          {{ busy ? 'Please wait…' : mode === 'sign-in' ? 'Sign in' : 'Create account' }}
        </button>
        <button class="quiet" type="button" @click="mode = mode === 'sign-in' ? 'sign-up' : 'sign-in'">
          {{ mode === 'sign-in' ? 'Need an account? Sign up' : 'Already registered? Sign in' }}
        </button>
      </form>

      <div v-else-if="!membership" class="workspace-options">
        <p>Signed in as <strong>{{ user.email }}</strong>.</p>
        <form class="access-form" @submit.prevent="createWorkspace">
          <h2>Create this app’s guild workspace</h2>
          <label for="guild-name">Guild or Discord server name</label>
          <input id="guild-name" v-model="guildName" maxlength="80" required>
          <label for="discord-id">Discord server ID <span>(optional)</span></label>
          <input id="discord-id" v-model="discordServerId" inputmode="numeric" maxlength="32">
          <button class="primary" type="submit" :disabled="busy || guildName.trim().length < 2">
            Create workspace as owner
          </button>
        </form>
        <form class="access-form" @submit.prevent="acceptInvite">
          <h2>Join an existing guild</h2>
          <label for="guild-invite">Invite code</label>
          <input id="guild-invite" v-model="inviteCode" autocomplete="off" required>
          <button type="submit" :disabled="busy || !inviteCode.trim()">Join guild</button>
        </form>
        <button class="quiet" type="button" @click="logOut">Sign out</button>
      </div>

      <p v-if="error" class="error" role="alert">{{ error }}</p>
      <p v-if="message" class="notice" role="status">{{ message }}</p>
    </section>
  </main>
</template>

<style scoped>
.access-page { min-height: 100vh; display: grid; place-items: center; padding: 24px; }
.access-card { width: min(100%, 520px); padding: clamp(20px, 5vw, 36px); display: grid; gap: 16px; }
.access-card h1, .access-card h2, .access-card p { margin: 0; }
.access-card h1 { font-family: var(--font-display); font-size: clamp(1.6rem, 5vw, 2.2rem); }
.access-card h2 { font-size: 1.1rem; }
.eyebrow { color: var(--fog); }
.access-form, .workspace-options { display: grid; gap: 10px; }
.access-form label { color: var(--fog); }
.access-form button { justify-self: start; }
.access-form label span { opacity: .7; }
.notice, .error { padding: 12px; border-radius: var(--r-sm); background: var(--ice-ridge); }
.error { color: #ffd1d1; }
code { overflow-wrap: anywhere; }
</style>
