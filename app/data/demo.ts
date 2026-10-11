import type { Character, RaidState } from '#shared/types'
import { SPEC_BY_ID } from './classes'

const c = (name: string, specId: string, role?: Character['role']): Character => ({
  id: name.toLowerCase(),
  name,
  classId: SPEC_BY_ID[specId]!.classId,
  specId,
  role: role ?? SPEC_BY_ID[specId]!.roles[0]!
})

const roster: Character[] = [
  c('Brannoc', 'warrior.protection'),
  c('Velaris', 'paladin.protection'),
  c('Thornhide', 'druid.feral', 'tank'),
  c('Lumiera', 'paladin.holy'),
  c('Seraphel', 'priest.discipline'),
  c('Oakenmend', 'druid.restoration'),
  c('Tidewhisper', 'shaman.restoration'),
  c('Mercya', 'priest.holy'),
  c('Kragath', 'warrior.fury'),
  c('Dawnblade', 'paladin.retribution'),
  c('Rimeclaw', 'deathknight.frost'),
  c('Gravelord', 'deathknight.unholy'),
  c('Stormfang', 'shaman.enhancement'),
  c('Nightveil', 'rogue.combat'),
  c('Shivra', 'rogue.assassination'),
  c('Duskbloom', 'druid.balance'),
  c('Frostweave', 'mage.frost'),
  c('Embrys', 'mage.fire'),
  c('Arcanos', 'mage.arcane'),
  c('Morthis', 'warlock.affliction'),
  c('Felgrin', 'warlock.demonology'),
  c('Umbrael', 'priest.shadow'),
  c('Thunderhorn', 'shaman.elemental'),
  c('Wildshot', 'hunter.marksmanship'),
  c('Snaretrap', 'hunter.survival'),
  c('Pyrrha', 'mage.fire'),
  c('Grimtusk', 'hunter.beastmastery')
]

export function demoRaid(): RaidState {
  const ids = roster.map(r => r.id)
  return {
    title: 'Icecrown Citadel, Thursday',
    size: 25,
    roster: structuredClone(roster),
    groups: [
      ['brannoc', 'velaris', 'thornhide', 'kragath', 'stormfang'],
      ['dawnblade', 'rimeclaw', 'gravelord', 'nightveil', 'shivra'],
      ['duskbloom', 'frostweave', 'embrys', 'thunderhorn', 'arcanos'],
      ['morthis', 'felgrin', 'umbrael', 'wildshot', 'snaretrap'],
      ['lumiera', 'seraphel', 'oakenmend', 'tidewhisper', 'mercya']
    ].map(g => g.filter(id => ids.includes(id)))
      .map(g => [...g, ...Array(5 - g.length).fill(null)])
  }
}

export function emptyRaid(): RaidState {
  return {
    title: 'New raid',
    size: 25,
    roster: [],
    groups: Array.from({ length: 5 }, () => Array(5).fill(null))
  }
}
