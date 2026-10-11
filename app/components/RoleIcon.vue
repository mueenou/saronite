<script setup lang="ts">
import type { Role } from '#shared/types'
defineProps<{ role: Role }>()
</script>

<template>
  <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round">
    <!-- tank: shield -->
    <path v-if="role === 'tank'" d="M8 1.5 13.5 3.5V8c0 3-2.4 5.3-5.5 6.5C4.9 13.3 2.5 11 2.5 8V3.5Z" />
    <!-- healer: cross -->
    <path v-else-if="role === 'healer'" d="M6 2h4v4h4v4h-4v4H6v-4H2V6h4Z" />
    <!-- melee: sword -->
    <g v-else-if="role === 'melee'">
      <path d="M13.5 2.5 6 10" /><path d="M13.5 2.5h-3M13.5 2.5v3" />
      <path d="M4 8l4 4" /><path d="M5 11l-2.5 2.5" />
    </g>
    <!-- ranged: bolt -->
    <path v-else d="M9 1.5 3.5 9h4L6.5 14.5 12.5 7h-4Z" />
  </svg>
</template>
