<script setup lang="ts">
import type { Role } from '#shared/types'
import { ROLE_LABEL, ROLE_TARGETS } from '~/data/classes'

const { placed, state } = useRaid()
const roles: Role[] = ['tank', 'healer', 'melee', 'ranged']

const rows = computed(() => roles.map((role) => {
  const count = placed.value.filter(p => p.character.role === role).length
  const [min, max] = ROLE_TARGETS[state.value.size][role]
  const status = count < min ? 'low' : count > max ? 'high' : 'ok'
  return { role, count, min, max, status }
}))
</script>

<template>
  <ul class="roles" aria-label="Role balance">
    <li v-for="r in rows" :key="r.role" :class="r.status" :title="`Suggested ${r.min}–${r.max}`">
      <RoleIcon :role="r.role" />
      <span class="count">{{ r.count }}</span>
      <span class="label">{{ ROLE_LABEL[r.role] }}</span>
      <span class="target muted">{{ r.min === r.max ? r.min : `${r.min}–${r.max}` }}</span>
    </li>
    <li class="total">
      <span class="count">{{ placed.length }}</span>
      <span class="label">of {{ state.size }}</span>
    </li>
  </ul>
</template>

<style scoped>
.roles { list-style: none; margin: 0; padding: 0; display: flex; flex-wrap: wrap; gap: 8px 20px; }
li { display: flex; align-items: center; gap: 6px; }
.count { font-family: var(--font-display); font-size: 1.5rem; line-height: 1; }
.label { color: var(--fog); }
.target { font-size: 0.8rem; }
.low .count { color: var(--missing); }
.high .count { color: var(--partial); }
.ok .count { color: var(--rime); }
.total { margin-left: auto; }
</style>
