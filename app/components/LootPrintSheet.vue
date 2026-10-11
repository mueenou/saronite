<script setup lang="ts">
import type { LootItemRecord } from '~/composables/useLoot'
import { CLASS_BY_ID } from '~/data/classes'

const loot = useLoot()
const raid = useRaid()
const { membership } = useGuild()
const { items, board } = loot
const { guildPlayers } = raid

const sheet = ref<HTMLElement | null>(null)
const zoom = ref(1)
const layoutWidth = ref(1062)

// A4 landscape printable area at 96 dpi with ~8 mm margins.
const PAGE_WIDTH = 1062
const PAGE_HEIGHT = 715
const MIN_ZOOM = 0.3
const MAX_ZOOM = 2

const sortedItems = computed(() => [...items.value].sort((a, b) => a.name.localeCompare(b.name)))
// Fewer, wider columns for short lists so the page fills evenly.
const columnCount = computed(() => sortedItems.value.length <= 4 ? 2 : sortedItems.value.length <= 12 ? 3 : 4)

function playerName(id: string) {
  return guildPlayers.value.find(player => player.id === id)?.name ?? id
}

function playerColor(id: string) {
  const player = guildPlayers.value.find(entry => entry.id === id)
  if (!player) return '#222'
  // Priest white and rogue yellow are unreadable on paper.
  if (player.classId === 'priest') return '#555'
  if (player.classId === 'rogue') return '#a89400'
  return CLASS_BY_ID[player.classId].color
}

function nextEligible(item: LootItemRecord) {
  const eligible = loot.eligibleCandidates(item.id)
  const top = eligible[0]?.priority
  return top === undefined ? [] : eligible.filter(candidate => candidate.priority === top)
}

function awardedTo(item: LootItemRecord) {
  return loot.awardsForItem(item.id).filter(award => !award.voidedAt)
}

async function waitForIcons() {
  const images = Array.from(sheet.value?.querySelectorAll('img') ?? [])
  await Promise.all(images.map(image => image.complete
    ? Promise.resolve()
    : new Promise<void>(resolve => {
        image.addEventListener('load', () => resolve(), { once: true })
        image.addEventListener('error', () => resolve(), { once: true })
        setTimeout(resolve, 4000)
      })))
}

// Unzoomed height when laid out at the width that `scale` would map onto the page.
async function heightAt(scale: number) {
  layoutWidth.value = PAGE_WIDTH / scale
  await nextTick()
  return sheet.value?.scrollHeight ?? PAGE_HEIGHT
}

async function fitZoom() {
  zoom.value = 1
  let low = MIN_ZOOM
  let high = MAX_ZOOM
  if ((await heightAt(high)) * high <= PAGE_HEIGHT) return high
  for (let step = 0; step < 14; step++) {
    const mid = (low + high) / 2
    if ((await heightAt(mid)) * mid <= PAGE_HEIGHT) low = mid
    else high = mid
  }
  return low
}

async function exportPdf() {
  zoom.value = 1
  layoutWidth.value = PAGE_WIDTH
  await nextTick()
  await waitForIcons()
  const scale = await fitZoom()
  layoutWidth.value = PAGE_WIDTH / scale
  zoom.value = scale
  await nextTick()
  const previousTitle = document.title
  document.title = `${membership.value?.guild.name ?? 'Guild'} - Loot attribution`
  window.print()
  document.title = previousTitle
}

defineExpose({ exportPdf })
</script>

<template>
  <Teleport to="body">
    <div class="print-root" aria-hidden="true">
      <div ref="sheet" class="print-sheet" :style="{ width: `${layoutWidth}px`, zoom }">
        <header class="print-header">
          <strong>{{ membership?.guild.name }} · Loot attribution</strong>
          <span>Round {{ board?.currentRound ?? 1 }} · {{ new Date().toLocaleDateString() }}</span>
        </header>
        <div class="print-columns" :style="{ columnCount }">
          <section v-for="item in sortedItems" :key="item.id" class="print-item">
            <div class="print-item-title">
              <img
                :src="`https://wow.zamimg.com/images/wow/icons/medium/${item.iconKey}.jpg`"
                alt=""
                @error="($event.target as HTMLImageElement).src = 'https://wow.zamimg.com/images/wow/icons/medium/inv_misc_questionmark.jpg'"
              >
              <strong>{{ item.name }}</strong>
              <span>{{ loot.awardCount(item.id) }}/{{ item.copies }}</span>
            </div>
            <div class="print-next">
              Next:
              <template v-if="nextEligible(item).length">
                <b v-for="(candidate, index) in nextEligible(item)" :key="candidate.playerId" :style="{ color: playerColor(candidate.playerId) }">
                  {{ playerName(candidate.playerId) }}<template v-if="index < nextEligible(item).length - 1">, </template>
                </b>
                <i v-if="nextEligible(item).length > 1"> (roll)</i>
              </template>
              <i v-else>{{ loot.awardCount(item.id) >= item.copies ? 'complete' : 'none this round' }}</i>
            </div>
            <div class="print-priority">
              <span
                v-for="candidate in loot.candidatesForItem(item.id)"
                :key="candidate.id"
                :class="{ passed: candidate.status === 'passed' }"
              ><em>{{ candidate.priority }}.</em> <b :style="{ color: playerColor(candidate.playerId) }">{{ playerName(candidate.playerId) }}</b></span>
              <span v-if="!loot.candidatesForItem(item.id).length" class="empty">no candidates</span>
            </div>
            <div v-if="awardedTo(item).length" class="print-awarded">
              Won: {{ awardedTo(item).map(award => `${playerName(award.playerId)} (R${award.round})`).join(', ') }}
            </div>
          </section>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style>
.print-root { position: absolute; left: -100000px; top: 0; visibility: hidden; pointer-events: none; background: #fff; }
.print-sheet { font: 11px/1.3 'Segoe UI', Arial, sans-serif; color: #111; overflow: hidden; }
.print-header { display: flex; justify-content: space-between; border-bottom: 2px solid #333; padding-bottom: 4px; margin-bottom: 6px; font-size: 14px; }
.print-columns { column-gap: 10px; }
.print-item { break-inside: avoid; border: 1px solid #bbb; border-radius: 3px; padding: 4px 6px; margin-bottom: 6px; }
.print-item-title { display: flex; align-items: center; gap: 6px; border-bottom: 1px solid #ddd; margin-bottom: 2px; padding-bottom: 2px; }
.print-item-title img { width: 1.8em; height: 1.8em; flex: 0 0 1.8em; border-radius: 2px; }
.print-item-title strong { flex: 1; min-width: 0; }
.print-item-title span, .print-priority em, .print-awarded, .print-priority .empty { color: #666; }
.print-next { margin-bottom: 2px; }
.print-priority { display: flex; flex-wrap: wrap; gap: 0 8px; }
.print-priority em { font-style: normal; }
.print-priority .passed { text-decoration: line-through; opacity: .6; }
.print-priority b, .print-next b { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
.print-awarded { font-size: 10px; margin-top: 2px; }

@media print {
  @page { size: A4 landscape; margin: 8mm; }
  body > *:not(.print-root) { display: none !important; }
  html, body { background: #fff !important; color: #111 !important; min-height: 0 !important; }
  .print-root { position: static !important; visibility: visible !important; }
}
</style>
