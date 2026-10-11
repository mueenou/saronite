import type { Effect } from '#shared/types'

/**
 * WotLK (3.3.5) raid buffs and debuffs.
 * Provider source is either a class id ("shaman") or a spec id ("shaman.enhancement").
 * This file is the backbone of the app: coverage, hints and boss templates all build on it.
 */
export const EFFECTS: Effect[] = [
  // ───────────── Buffs ─────────────
  {
    id: 'bloodlust', kind: 'buff', name: 'Bloodlust / Heroism',
    description: '30% haste for 40 seconds.',
    relevantTo: ['tank', 'healer', 'melee', 'ranged'],
    providers: [{ source: 'shaman', ability: 'Bloodlust / Heroism', scope: 'raid' }]
  },
  {
    id: 'replenishment', kind: 'buff', name: 'Replenishment',
    description: 'Restores 1% of max mana every 5 seconds to 10 party or raid members.',
    relevantTo: ['healer', 'ranged'],
    providers: [
      { source: 'paladin.retribution', ability: 'Judgements of the Wise', scope: 'raid' },
      { source: 'priest.shadow', ability: 'Vampiric Touch', scope: 'raid' },
      { source: 'hunter.survival', ability: 'Hunting Party', scope: 'raid' },
      { source: 'warlock.destruction', ability: 'Improved Soul Leech', scope: 'raid' },
      { source: 'mage.frost', ability: 'Enduring Winter', scope: 'raid' }
    ]
  },
  {
    id: 'damage-3', kind: 'buff', name: '3% damage',
    description: 'All damage increased by 3%.',
    relevantTo: ['melee', 'ranged', 'tank'],
    providers: [
      { source: 'paladin.retribution', ability: 'Sanctified Retribution', scope: 'raid' },
      { source: 'mage.arcane', ability: 'Arcane Empowerment', scope: 'raid' },
      { source: 'hunter.beastmastery', ability: 'Ferocious Inspiration', scope: 'raid' }
    ]
  },
  {
    id: 'haste-3', kind: 'buff', name: '3% haste',
    description: 'All haste increased by 3%.',
    relevantTo: ['melee', 'ranged', 'healer', 'tank'],
    providers: [
      { source: 'druid.balance', ability: 'Improved Moonkin Form', scope: 'raid' },
      { source: 'paladin.retribution', ability: 'Swift Retribution', scope: 'raid' }
    ]
  },
  {
    id: 'melee-haste', kind: 'buff', name: '20% melee haste',
    description: 'Melee and ranged attack speed increased by 20%.',
    relevantTo: ['melee', 'tank'],
    providers: [
      { source: 'shaman', ability: 'Windfury Totem (air)', scope: 'party' },
      { source: 'deathknight.frost', ability: 'Improved Icy Talons', scope: 'raid' }
    ]
  },
  {
    id: 'spell-haste', kind: 'buff', name: '5% spell haste',
    description: 'Spell haste increased by 5%.',
    relevantTo: ['ranged', 'healer'],
    providers: [{ source: 'shaman', ability: 'Wrath of Air Totem (air)', scope: 'party' }]
  },
  {
    id: 'physical-crit', kind: 'buff', name: '5% physical crit',
    description: 'Melee and ranged critical strike chance increased by 5%.',
    relevantTo: ['melee', 'tank'],
    providers: [
      { source: 'druid.feral', ability: 'Leader of the Pack', scope: 'raid' },
      { source: 'warrior.fury', ability: 'Rampage', scope: 'raid' }
    ]
  },
  {
    id: 'spell-crit', kind: 'buff', name: '5% spell crit',
    description: 'Spell critical strike chance increased by 5%.',
    relevantTo: ['ranged', 'healer'],
    providers: [
      { source: 'druid.balance', ability: 'Moonkin Aura', scope: 'raid' },
      { source: 'shaman.elemental', ability: 'Elemental Oath', scope: 'raid' }
    ]
  },
  {
    id: 'attack-power-10', kind: 'buff', name: '10% attack power',
    description: 'Attack power increased by 10%.',
    relevantTo: ['melee', 'tank'],
    providers: [
      { source: 'deathknight.blood', ability: "Abomination's Might", scope: 'raid' },
      { source: 'hunter.marksmanship', ability: 'Trueshot Aura', scope: 'raid' },
      { source: 'shaman.enhancement', ability: 'Unleashed Rage', scope: 'raid' }
    ]
  },
  {
    id: 'attack-power-flat', kind: 'buff', name: 'Flat attack power',
    description: 'Battle Shout or Blessing of Might.',
    relevantTo: ['melee', 'tank'],
    providers: [
      { source: 'warrior', ability: 'Battle Shout', scope: 'raid' },
      { source: 'paladin', ability: 'Blessing of Might', scope: 'raid' }
    ]
  },
  {
    id: 'strength-agility', kind: 'buff', name: 'Strength and agility',
    description: 'Horn of Winter or Strength of Earth Totem.',
    relevantTo: ['melee', 'tank'],
    providers: [
      { source: 'deathknight', ability: 'Horn of Winter', scope: 'raid' },
      { source: 'shaman', ability: 'Strength of Earth Totem (earth)', scope: 'party' }
    ]
  },
  {
    id: 'spell-power', kind: 'buff', name: 'Spell power',
    description: 'Totem of Wrath, Demonic Pact or Flametongue Totem.',
    relevantTo: ['ranged', 'healer'],
    providers: [
      { source: 'shaman.elemental', ability: 'Totem of Wrath (fire)', scope: 'party' },
      { source: 'warlock.demonology', ability: 'Demonic Pact', scope: 'raid' },
      { source: 'shaman', ability: 'Flametongue Totem (fire)', scope: 'party' }
    ]
  },
  {
    id: 'kings', kind: 'buff', name: 'Blessing of Kings',
    description: 'All stats increased by 10%.',
    relevantTo: ['tank', 'healer', 'melee', 'ranged'],
    providers: [{ source: 'paladin', ability: 'Blessing of Kings', scope: 'raid' }]
  },
  {
    id: 'mark-of-the-wild', kind: 'buff', name: 'Mark of the Wild',
    description: 'All stats, armor and resistances.',
    relevantTo: ['tank', 'healer', 'melee', 'ranged'],
    providers: [{ source: 'druid', ability: 'Gift of the Wild', scope: 'raid' }]
  },
  {
    id: 'fortitude', kind: 'buff', name: 'Fortitude',
    description: 'Stamina increased.',
    relevantTo: ['tank', 'healer', 'melee', 'ranged'],
    providers: [{ source: 'priest', ability: 'Prayer of Fortitude', scope: 'raid' }]
  },
  {
    id: 'intellect', kind: 'buff', name: 'Intellect',
    description: 'Arcane Brilliance or Fel Intelligence.',
    relevantTo: ['healer', 'ranged'],
    providers: [
      { source: 'mage', ability: 'Arcane Brilliance', scope: 'raid' },
      { source: 'warlock', ability: 'Fel Intelligence (felhunter)', scope: 'party' }
    ]
  },
  {
    id: 'mana-regen', kind: 'buff', name: 'Mana per 5',
    description: 'Blessing of Wisdom or Mana Spring Totem.',
    relevantTo: ['healer', 'ranged'],
    providers: [
      { source: 'paladin', ability: 'Blessing of Wisdom', scope: 'raid' },
      { source: 'shaman', ability: 'Mana Spring Totem (water)', scope: 'party' }
    ]
  },
  {
    id: 'health', kind: 'buff', name: 'Max health',
    description: 'Commanding Shout or Blood Pact.',
    relevantTo: ['tank', 'healer', 'melee', 'ranged'],
    providers: [
      { source: 'warrior', ability: 'Commanding Shout', scope: 'raid' },
      { source: 'warlock', ability: 'Blood Pact (imp)', scope: 'party' }
    ]
  },
  {
    id: 'damage-reduction-3', kind: 'buff', name: '3% damage reduction',
    description: 'Blessing of Sanctuary or Renewed Hope.',
    relevantTo: ['tank'],
    providers: [
      { source: 'paladin.protection', ability: 'Blessing of Sanctuary', scope: 'raid' },
      { source: 'priest.discipline', ability: 'Renewed Hope', scope: 'raid' }
    ]
  },
  {
    id: 'healing-received', kind: 'buff', name: '6% healing received',
    description: 'Improved Devotion Aura or Tree of Life.',
    relevantTo: ['tank'],
    providers: [
      { source: 'paladin.protection', ability: 'Improved Devotion Aura', scope: 'raid' },
      { source: 'paladin.holy', ability: 'Improved Devotion Aura', scope: 'raid' },
      { source: 'druid.restoration', ability: 'Tree of Life', scope: 'raid' }
    ]
  },

  // ───────────── Debuffs ─────────────
  {
    id: 'armor-major', kind: 'debuff', name: 'Major armor reduction',
    description: 'Target armor reduced by 20%.',
    relevantTo: ['melee', 'tank'],
    providers: [
      { source: 'warrior', ability: 'Sunder Armor', scope: 'raid' },
      { source: 'rogue', ability: 'Expose Armor', scope: 'raid' },
      { source: 'hunter', ability: 'Acid Spit (worm)', scope: 'raid' }
    ]
  },
  {
    id: 'armor-minor', kind: 'debuff', name: 'Minor armor reduction',
    description: 'Target armor reduced by 5%.',
    relevantTo: ['melee', 'tank'],
    providers: [
      { source: 'druid', ability: 'Faerie Fire', scope: 'raid' },
      { source: 'warlock', ability: 'Curse of Weakness', scope: 'raid' },
      { source: 'hunter', ability: 'Sting (wasp)', scope: 'raid' }
    ]
  },
  {
    id: 'physical-damage-taken', kind: 'debuff', name: '4% physical damage taken',
    description: 'Blood Frenzy or Savage Combat.',
    relevantTo: ['melee', 'tank'],
    providers: [
      { source: 'warrior.arms', ability: 'Blood Frenzy', scope: 'raid' },
      { source: 'rogue.combat', ability: 'Savage Combat', scope: 'raid' }
    ]
  },
  {
    id: 'spell-damage-taken', kind: 'debuff', name: '13% spell damage taken',
    description: 'Curse of the Elements, Ebon Plaguebringer or Earth and Moon.',
    relevantTo: ['ranged'],
    providers: [
      { source: 'warlock', ability: 'Curse of the Elements', scope: 'raid' },
      { source: 'deathknight.unholy', ability: 'Ebon Plaguebringer', scope: 'raid' },
      { source: 'druid.balance', ability: 'Earth and Moon', scope: 'raid' }
    ]
  },
  {
    id: 'spell-hit-taken', kind: 'debuff', name: '3% spell hit',
    description: 'Misery or Improved Faerie Fire.',
    relevantTo: ['ranged'],
    providers: [
      { source: 'priest.shadow', ability: 'Misery', scope: 'raid' },
      { source: 'druid.balance', ability: 'Improved Faerie Fire', scope: 'raid' }
    ]
  },
  {
    id: 'spell-crit-taken', kind: 'debuff', name: '5% spell crit taken',
    description: 'Improved Scorch, Winter\'s Chill or Improved Shadow Bolt.',
    relevantTo: ['ranged'],
    providers: [
      { source: 'mage.fire', ability: 'Improved Scorch', scope: 'raid' },
      { source: 'mage.frost', ability: "Winter's Chill", scope: 'raid' },
      { source: 'warlock.destruction', ability: 'Improved Shadow Bolt', scope: 'raid' }
    ]
  },
  {
    id: 'crit-taken', kind: 'debuff', name: '3% crit taken',
    description: 'Heart of the Crusader, Totem of Wrath or Master Poisoner.',
    relevantTo: ['melee', 'ranged'],
    providers: [
      { source: 'paladin.retribution', ability: 'Heart of the Crusader', scope: 'raid' },
      { source: 'shaman.elemental', ability: 'Totem of Wrath', scope: 'raid' },
      { source: 'rogue.assassination', ability: 'Master Poisoner', scope: 'raid' }
    ]
  },
  {
    id: 'bleed-damage', kind: 'debuff', name: '30% bleed damage',
    description: 'Mangle or Trauma.',
    relevantTo: ['melee'],
    providers: [
      { source: 'druid.feral', ability: 'Mangle', scope: 'raid' },
      { source: 'warrior.arms', ability: 'Trauma', scope: 'raid' }
    ]
  },
  {
    id: 'attack-power-reduction', kind: 'debuff', name: 'Attack power reduction',
    description: 'Lowers the boss\'s damage output.',
    relevantTo: ['tank'],
    providers: [
      { source: 'warrior', ability: 'Demoralizing Shout', scope: 'raid' },
      { source: 'druid.feral', ability: 'Demoralizing Roar', scope: 'raid' },
      { source: 'paladin.protection', ability: 'Vindication', scope: 'raid' },
      { source: 'paladin.retribution', ability: 'Vindication', scope: 'raid' }
    ]
  },
  {
    id: 'attack-speed-reduction', kind: 'debuff', name: 'Attack speed reduction',
    description: 'Slows the boss\'s melee attacks.',
    relevantTo: ['tank'],
    providers: [
      { source: 'warrior', ability: 'Thunder Clap', scope: 'raid' },
      { source: 'deathknight', ability: 'Frost Fever', scope: 'raid' },
      { source: 'druid.feral', ability: 'Infected Wounds', scope: 'raid' },
      { source: 'paladin.protection', ability: 'Judgements of the Just', scope: 'raid' }
    ]
  }
]
