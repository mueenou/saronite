<script setup lang="ts">
import type { EffectCoverage } from '~/utils/coverage'

const props = defineProps<{ coverage?: EffectCoverage[] }>()
const raidCoverage = props.coverage ? null : useRaid().coverage
const coverage = computed(() => props.coverage ?? raidCoverage?.value ?? [])

const sections = computed(() => [
  { title: 'Buffs', items: coverage.value.filter(c => c.effect.kind === 'buff') },
  { title: 'Debuffs', items: coverage.value.filter(c => c.effect.kind === 'debuff') }
])

const statusLabel = { covered: 'Covered', partial: 'Some groups', missing: 'Missing' } as const

function count(items: EffectCoverage[]) {
  return items.filter(i => i.status === 'covered').length
}

function uniqueSources(item: EffectCoverage) {
  const seen = new Set<string>()
  return item.sources.filter((s) => {
    const key = `${s.character.id}:${s.provider.ability}`
    if (seen.has(key)) return false
    seen.add(key)
    return true
  })
}
</script>

<template>
  <section class="board panel" aria-label="Buff and debuff coverage">
    <div v-for="section in sections" :key="section.title" class="section">
      <header>
        <h2>{{ section.title }}</h2>
        <span class="tally">{{ count(section.items) }} / {{ section.items.length }}</span>
      </header>
      <ul>
        <li v-for="item in section.items" :key="item.effect.id">
          <details :class="item.status">
            <summary>
              <span class="dot" :title="statusLabel[item.status]" />
              <span class="name">{{ item.effect.name }}</span>
              <span v-if="item.status === 'partial'" class="tag">
                {{ item.missingGroups.length > 1 ? 'Groups' : 'Group' }} {{ item.missingGroups.map(g => g + 1).join(', ') }} {{ item.missingGroups.length > 1 ? 'lack' : 'lacks' }} it
              </span>
              <span class="visually-hidden">{{ statusLabel[item.status] }}</span>
            </summary>
            <div class="detail">
              <p class="muted">{{ item.effect.description }}</p>
              <p v-if="item.sources.length" class="sources">
                <span v-for="s in uniqueSources(item)" :key="s.character.id + s.provider.ability">
                  {{ s.character.name }}: {{ s.provider.ability }}<template v-if="s.provider.scope === 'party'"> (group {{ s.group + 1 }} only)</template>
                </span>
              </p>
              <p v-else class="sources">
                Bring one of:
                <span v-for="p in item.effect.providers" :key="p.source + p.ability">{{ p.ability }}</span>
              </p>
            </div>
          </details>
        </li>
      </ul>
    </div>
  </section>
</template>

<style scoped>
.board { display: grid; gap: 20px; align-content: start; }
header { display: flex; align-items: baseline; justify-content: space-between; margin-bottom: 8px; }
h2 { font-size: 1.3rem; }
.tally { font-family: var(--font-display); color: var(--frost); font-size: 1.1rem; }
ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 2px; }
summary {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 6px 4px;
  cursor: pointer;
  list-style: none;
  border-radius: var(--r-sm);
}
summary::-webkit-details-marker { display: none; }
summary:hover { background: var(--ice-ridge); }
.dot {
  width: 10px; height: 10px; flex: none;
  transform: rotate(45deg);
  border: 2px solid var(--missing);
}
.covered .dot { background: var(--ok); border-color: var(--ok); }
.partial .dot { background: linear-gradient(135deg, var(--partial) 50%, transparent 50%); border-color: var(--partial); }
.missing .name { color: var(--fog); }
.name { flex: 1; }
.tag { font-size: 0.78rem; color: var(--partial); white-space: nowrap; }
.detail { padding: 2px 4px 10px 24px; font-size: 0.9rem; }
.detail p { margin: 0 0 4px; }
.sources { display: flex; flex-wrap: wrap; gap: 4px 12px; }
</style>
