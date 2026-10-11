import type { LootAwardRecord, LootCandidateRecord, LootItemRecord } from '~/composables/useLoot'
import type { GuildPlayer } from '#shared/types'

// Plain single-line text so it survives WoW edit boxes: no "|" (WoW escape char)
// and no newlines. Records are split by ";", fields by "," and lists by "/".
export const WA_BOARD_PREFIX = 'SARONITE:1'
export const WA_LOG_PREFIX = 'SARONITE-LOG:1'

function clean(value: string) {
  return value.replace(/[;:,/|\r\n]/g, ' ').trim()
}

export function normalizeName(name: string) {
  return name.split('-')[0]!.trim().toLocaleLowerCase()
}

export function encodeBoardForWeakAura(input: {
  guildName: string
  round: number
  items: LootItemRecord[]
  candidates: LootCandidateRecord[]
  awards: LootAwardRecord[]
  players: GuildPlayer[]
  version: number
}) {
  const name = (id: string) => clean(input.players.find(player => player.id === id)?.name ?? '')
  const active = input.awards.filter(award => !award.voidedAt)
  const received = [...new Set(active.filter(award => award.round === input.round).map(award => name(award.playerId)))].filter(Boolean)
  const records = [
    WA_BOARD_PREFIX,
    `v:${input.version}`,
    `r:${input.round}`,
    `g:${clean(input.guildName)}`,
    `x:${received.join('/')}`
  ]
  for (const item of input.items) {
    if (!item.itemId) continue
    const awarded = active.filter(award => award.itemId === item.id).length
    const list = input.candidates
      .filter(candidate => candidate.itemId === item.id && name(candidate.playerId))
      .sort((a, b) => a.priority - b.priority)
      .map(candidate => `${name(candidate.playerId)}:${candidate.priority}:${candidate.status === 'passed' ? 'p' : 'a'}`)
    records.push(`i:${item.itemId},${item.copies},${awarded},${list.join('/')}`)
  }
  return records.join(';')
}

export interface WeakAuraLogEntry { gameItemId: number, name: string, round: number, override: boolean }
export interface WeakAuraLog { version: number, finalRound: number, entries: WeakAuraLogEntry[] }

export function parseWeakAuraLog(text: string): WeakAuraLog {
  const records = text.trim().split(';').map(record => record.trim()).filter(Boolean)
  if (records[0] !== WA_LOG_PREFIX) throw new Error('This is not a Saronite WeakAura export. Use Export on the Saronite bar in game.')
  const log: WeakAuraLog = { version: 0, finalRound: 0, entries: [] }
  for (const record of records.slice(1)) {
    const [key, ...rest] = record.split(':')
    const value = rest.join(':')
    if (key === 'v') log.version = Number(value) || 0
    else if (key === 'r') log.finalRound = Number(value) || 0
    else if (key === 'a') {
      const [itemId, name, round, override] = value.split(',')
      const gameItemId = Number(itemId)
      if (!gameItemId || !name) continue
      log.entries.push({ gameItemId, name: name.trim(), round: Number(round) || 0, override: override === '1' })
    }
  }
  return log
}
