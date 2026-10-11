import type { Character, ClassId, RaidSize, RaidState, Role } from '#shared/types'

/** Compact, URL-safe encoding of a raid so it can be shared as a link */
type Packed = {
  t: string
  s: RaidSize
  r: [string, string, ClassId, string, Role][]
  g: (string | null)[][]
}

function toBase64Url(text: string): string {
  const bytes = new TextEncoder().encode(text)
  let bin = ''
  bytes.forEach(b => (bin += String.fromCharCode(b)))
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function fromBase64Url(code: string): string {
  const b64 = code.replace(/-/g, '+').replace(/_/g, '/')
  const bin = atob(b64)
  return new TextDecoder().decode(Uint8Array.from(bin, ch => ch.charCodeAt(0)))
}

export function encodeRaid(state: RaidState): string {
  const packed: Packed = {
    t: state.title,
    s: state.size,
    r: state.roster.map(c => [c.id, c.name, c.classId, c.specId, c.role]),
    g: state.groups
  }
  return toBase64Url(JSON.stringify(packed))
}

export function decodeRaid(code: string): RaidState | null {
  try {
    const p = JSON.parse(fromBase64Url(code)) as Packed
    const roster: Character[] = p.r.map(([id, name, classId, specId, role]) => ({ id, name, classId, specId, role }))
    return { title: p.t, size: p.s, roster, groups: p.g }
  } catch {
    return null
  }
}
