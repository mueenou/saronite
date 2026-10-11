import type { Character, Effect, Provider, RaidState, Role } from '#shared/types'
import { EFFECTS } from '~/data/effects'
import { CLASS_BY_ID } from '~/data/classes'

export type CoverageStatus = 'covered' | 'partial' | 'missing'

export interface CoverageSource {
  character: Character
  provider: Provider
  group: number
}

export interface EffectCoverage {
  effect: Effect
  status: CoverageStatus
  sources: CoverageSource[]
  /** groups (0-based) that need a party-only effect but don't have it */
  missingGroups: number[]
}

export interface Hint {
  id: string
  tone: 'warn' | 'info'
  text: string
}

export interface PlacedCharacter {
  character: Character
  group: number
}

export function providesFrom(character: Character, provider: Provider): boolean {
  return provider.source.includes('.')
    ? provider.source === character.specId
    : provider.source === character.classId
}

export function visibleGroupCount(state: RaidState): number {
  return state.size === 10 ? 2 : 5
}

export function placedCharacters(state: RaidState): PlacedCharacter[] {
  const byId = new Map(state.roster.map(c => [c.id, c]))
  const out: PlacedCharacter[] = []
  state.groups.slice(0, visibleGroupCount(state)).forEach((slots, group) => {
    for (const id of slots) {
      const character = id ? byId.get(id) : undefined
      if (character) out.push({ character, group })
    }
  })
  return out
}

function groupsNeeding(placed: PlacedCharacter[], roles: Role[]): Set<number> {
  return new Set(placed.filter(p => roles.includes(p.character.role)).map(p => p.group))
}

export function computeCoverage(state: RaidState): EffectCoverage[] {
  const placed = placedCharacters(state)

  return EFFECTS.map((effect) => {
    const sources: CoverageSource[] = []
    for (const p of placed) {
      for (const provider of effect.providers) {
        if (providesFrom(p.character, provider)) {
          sources.push({ character: p.character, provider, group: p.group })
        }
      }
    }

    if (sources.length === 0) {
      return { effect, status: 'missing', sources, missingGroups: [] }
    }
    if (sources.some(s => s.provider.scope === 'raid')) {
      return { effect, status: 'covered', sources, missingGroups: [] }
    }

    // Only party-scoped sources: check every group that cares about this effect
    const coveredGroups = new Set(sources.map(s => s.group))
    const missingGroups = [...groupsNeeding(placed, effect.relevantTo)]
      .filter(g => !coveredGroups.has(g))
      .sort((a, b) => a - b)

    return {
      effect,
      status: missingGroups.length ? 'partial' : 'covered',
      sources,
      missingGroups
    }
  })
}

export function computeHints(state: RaidState, coverage: EffectCoverage[]): Hint[] {
  const hints: Hint[] = []
  const placed = placedCharacters(state)
  if (placed.length === 0) return hints

  // 1. Party-only effects that miss some groups
  for (const c of coverage) {
    if (c.status !== 'partial') continue
    const abilities = [...new Set(c.sources.map(s => s.provider.ability.replace(/\s*\(.*\)$/, '')))].join(' / ')
    const n = c.missingGroups.length
    const groups = c.missingGroups.map(g => g + 1).join(', ')
    hints.push({
      id: `partial-${c.effect.id}`,
      tone: 'warn',
      text: `${c.effect.name} (${abilities}) only works inside the provider's group. Group${n > 1 ? 's' : ''} ${groups} ${n > 1 ? 'have' : 'has'} nobody bringing it.`
    })
  }

  // 2. One shaman can drop only one air totem
  const raidHasIcyTalons = coverage
    .find(c => c.effect.id === 'melee-haste')
    ?.sources.some(s => s.provider.scope === 'raid')

  for (let g = 0; g < visibleGroupCount(state); g++) {
    const members = placed.filter(p => p.group === g).map(p => p.character)
    const shamans = members.filter(m => m.classId === 'shaman').length
    if (shamans !== 1) continue
    const physical = members.some(m => m.role === 'melee' || m.role === 'tank')
    const casters = members.some(m => (m.role === 'ranged' || m.role === 'healer') && m.classId !== 'shaman')
    if (physical && casters && !raidHasIcyTalons) {
      hints.push({
        id: `air-${g}`,
        tone: 'info',
        text: `Group ${g + 1} mixes melee and casters with one shaman. Windfury and Wrath of Air are both air totems, so only one side gets its buff.`
      })
    }
  }

  // 3. Paladin blessings are limited to one per paladin per player
  const paladins = placed.filter(p => p.character.classId === 'paladin').length
  const wanted = ['Kings', 'Might', 'Wisdom']
  if (placed.some(p => p.character.specId === 'paladin.protection')) wanted.push('Sanctuary')
  if (paladins > 0 && paladins < wanted.length) {
    hints.push({
      id: 'blessings',
      tone: 'info',
      text: `${paladins} paladin${paladins > 1 ? 's' : ''} means ${paladins} blessing${paladins > 1 ? 's' : ''} per player. Wanted: ${wanted.join(', ')}. Warriors (Battle Shout) and shamans (Mana Spring) can cover Might and Wisdom.`
    })
  }

  // 4. Classes that bring a lot of value but are absent
  const present = new Set(placed.map(p => p.character.classId))
  if (state.size === 25) {
    for (const id of ['shaman', 'paladin', 'druid'] as const) {
      if (!present.has(id)) {
        hints.push({
          id: `absent-${id}`,
          tone: 'info',
          text: `No ${CLASS_BY_ID[id].name.toLowerCase()} in the raid. Check the board for what that removes.`
        })
      }
    }
  }

  return hints
}
