import type { ClassId, Role, Spec, WowClass } from '#shared/types'

const spec = (classId: ClassId, key: string, name: string, roles: Role[]): Spec => ({
  id: `${classId}.${key}`,
  classId,
  name,
  roles
})

export const CLASSES: WowClass[] = [
  {
    id: 'deathknight', name: 'Death Knight', color: '#C41E3A',
    specs: [
      spec('deathknight', 'blood', 'Blood', ['tank', 'melee']),
      spec('deathknight', 'frost', 'Frost', ['melee', 'tank']),
      spec('deathknight', 'unholy', 'Unholy', ['melee', 'tank'])
    ]
  },
  {
    id: 'druid', name: 'Druid', color: '#FF7C0A',
    specs: [
      spec('druid', 'balance', 'Balance', ['ranged']),
      spec('druid', 'feral', 'Feral', ['melee', 'tank']),
      spec('druid', 'restoration', 'Restoration', ['healer'])
    ]
  },
  {
    id: 'hunter', name: 'Hunter', color: '#AAD372',
    specs: [
      spec('hunter', 'beastmastery', 'Beast Mastery', ['ranged']),
      spec('hunter', 'marksmanship', 'Marksmanship', ['ranged']),
      spec('hunter', 'survival', 'Survival', ['ranged'])
    ]
  },
  {
    id: 'mage', name: 'Mage', color: '#3FC7EB',
    specs: [
      spec('mage', 'arcane', 'Arcane', ['ranged']),
      spec('mage', 'fire', 'Fire', ['ranged']),
      spec('mage', 'frost', 'Frost', ['ranged'])
    ]
  },
  {
    id: 'paladin', name: 'Paladin', color: '#F48CBA',
    specs: [
      spec('paladin', 'holy', 'Holy', ['healer']),
      spec('paladin', 'protection', 'Protection', ['tank']),
      spec('paladin', 'retribution', 'Retribution', ['melee'])
    ]
  },
  {
    id: 'priest', name: 'Priest', color: '#FFFFFF',
    specs: [
      spec('priest', 'discipline', 'Discipline', ['healer']),
      spec('priest', 'holy', 'Holy', ['healer']),
      spec('priest', 'shadow', 'Shadow', ['ranged'])
    ]
  },
  {
    id: 'rogue', name: 'Rogue', color: '#FFF468',
    specs: [
      spec('rogue', 'assassination', 'Assassination', ['melee']),
      spec('rogue', 'combat', 'Combat', ['melee']),
      spec('rogue', 'subtlety', 'Subtlety', ['melee'])
    ]
  },
  {
    id: 'shaman', name: 'Shaman', color: '#0070DD',
    specs: [
      spec('shaman', 'elemental', 'Elemental', ['ranged']),
      spec('shaman', 'enhancement', 'Enhancement', ['melee']),
      spec('shaman', 'restoration', 'Restoration', ['healer'])
    ]
  },
  {
    id: 'warlock', name: 'Warlock', color: '#8788EE',
    specs: [
      spec('warlock', 'affliction', 'Affliction', ['ranged']),
      spec('warlock', 'demonology', 'Demonology', ['ranged']),
      spec('warlock', 'destruction', 'Destruction', ['ranged'])
    ]
  },
  {
    id: 'warrior', name: 'Warrior', color: '#C69B6D',
    specs: [
      spec('warrior', 'arms', 'Arms', ['melee']),
      spec('warrior', 'fury', 'Fury', ['melee']),
      spec('warrior', 'protection', 'Protection', ['tank'])
    ]
  }
]

export const CLASS_BY_ID = Object.fromEntries(CLASSES.map(c => [c.id, c])) as Record<ClassId, WowClass>

export const SPEC_BY_ID: Record<string, Spec> = Object.fromEntries(
  CLASSES.flatMap(c => c.specs).map(s => [s.id, s])
)

export const ROLE_LABEL: Record<Role, string> = {
  tank: 'Tanks',
  healer: 'Healers',
  melee: 'Melee',
  ranged: 'Ranged'
}

/** Rough targets for a balanced composition: [min, max] */
export const ROLE_TARGETS: Record<10 | 25, Record<Role, [number, number]>> = {
  10: { tank: [2, 2], healer: [2, 3], melee: [2, 4], ranged: [2, 4] },
  25: { tank: [2, 3], healer: [5, 7], melee: [5, 9], ranged: [6, 10] }
}
