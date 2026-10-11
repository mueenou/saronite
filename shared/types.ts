export type ClassId =
  | 'warrior' | 'paladin' | 'hunter' | 'rogue' | 'priest'
  | 'deathknight' | 'shaman' | 'mage' | 'warlock' | 'druid'

export type Role = 'tank' | 'healer' | 'melee' | 'ranged'

export interface Spec {
  id: string            // e.g. "paladin.retribution"
  classId: ClassId
  name: string
  roles: Role[]         // first role is the default
}

export interface WowClass {
  id: ClassId
  name: string
  color: string
  specs: Spec[]
}

export interface Character {
  id: string
  name: string
  classId: ClassId
  specId: string
  role: Role
}

/** raid = whole raid benefits, party = only the provider's group */
export type Scope = 'raid' | 'party'

export interface Provider {
  /** "shaman" (any spec) or "shaman.enhancement" (that spec only) */
  source: string
  ability: string
  scope: Scope
}

export interface Effect {
  id: string
  name: string
  kind: 'buff' | 'debuff'
  description: string
  providers: Provider[]
  /** roles that actually care about this effect (used for group hints) */
  relevantTo: Role[]
}

export type RaidSize = 10 | 25

export interface RaidState {
  title: string
  size: RaidSize
  roster: Character[]
  /** 5 groups x 5 slots of character ids (10-man uses the first 2 groups) */
  groups: (string | null)[][]
}

/** A raid persisted in the Supabase guild workspace. */
export interface SavedRaid extends RaidState {
  id: string
  createdAt: string
  updatedAt: string
}

export type GuildRole = 'owner' | 'admin' | 'officer' | 'member'

export interface Guild {
  id: string
  name: string
  discordServerId: string | null
}

export interface GuildPlayer {
  id: string
  name: string
  classId: ClassId
  specId: string
  role: Role
}
