/**
 * Input validation helpers for Supabase Edge Functions.
 *
 * Validates at the system boundary (incoming request bodies)
 * before any database operations happen.
 */

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})?)?$/

export class ValidationError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'ValidationError'
  }
}

/** Throws ValidationError if condition is false */
function check(condition: boolean, message: string): asserts condition {
  if (!condition) throw new ValidationError(message)
}

export function isUUID(value: unknown): value is string {
  return typeof value === 'string' && UUID_RE.test(value)
}

export function requireUUID(value: unknown, field: string): string {
  check(isUUID(value), `${field} must be a valid UUID`)
  return value
}

export function requireString(value: unknown, field: string, maxLength = 5000): string {
  check(typeof value === 'string' && value.trim().length > 0, `${field} is required`)
  check(value.length <= maxLength, `${field} must be ${maxLength} characters or less`)
  return value.trim()
}

export function optionalString(value: unknown, field: string, maxLength = 5000): string | null {
  if (value == null || value === '') return null
  check(typeof value === 'string', `${field} must be a string`)
  check(value.length <= maxLength, `${field} must be ${maxLength} characters or less`)
  return value.trim()
}

export function requireInt(value: unknown, field: string, min?: number, max?: number): number {
  const num = Number(value)
  check(Number.isInteger(num), `${field} must be an integer`)
  if (min != null) check(num >= min, `${field} must be at least ${min}`)
  if (max != null) check(num <= max, `${field} must be at most ${max}`)
  return num
}

export function requireNumber(value: unknown, field: string, min?: number, max?: number): number {
  const num = Number(value)
  check(Number.isFinite(num), `${field} must be a number`)
  if (min != null) check(num >= min, `${field} must be at least ${min}`)
  if (max != null) check(num <= max, `${field} must be at most ${max}`)
  return num
}

export function requireEnum<T extends string>(value: unknown, field: string, allowed: T[]): T {
  check(typeof value === 'string' && allowed.includes(value as T),
    `${field} must be one of: ${allowed.join(', ')}`)
  return value as T
}

export function requireArray(value: unknown, field: string, minLength = 1, maxLength = 1000): unknown[] {
  check(Array.isArray(value), `${field} must be an array`)
  check(value.length >= minLength, `${field} must have at least ${minLength} item(s)`)
  check(value.length <= maxLength, `${field} must have at most ${maxLength} items`)
  return value
}

export function optionalISO(value: unknown, field: string): string | null {
  if (value == null || value === '') return null
  check(typeof value === 'string' && ISO_DATE_RE.test(value), `${field} must be a valid ISO date`)
  return value
}

export function optionalBoolean(value: unknown, _field: string): boolean {
  if (value == null) return false
  return !!value
}

// -------------------------------------------------------
// Domain-specific validators
// -------------------------------------------------------

export interface ValidatedRoundPlayer {
  player_id?: string
  tee_id: string
  guest_info?: { display_name: string; handicap_index: number; gender?: string }
}

export function validateRoundPlayer(p: unknown, index: number): ValidatedRoundPlayer {
  check(typeof p === 'object' && p !== null, `players[${index}] must be an object`)
  const obj = p as Record<string, unknown>

  const hasPlayerId = obj.player_id != null && obj.player_id !== ''
  const hasGuestInfo = obj.guest_info != null

  check(hasPlayerId || hasGuestInfo, `players[${index}] must have player_id or guest_info`)

  const tee_id = requireUUID(obj.tee_id, `players[${index}].tee_id`)

  if (hasPlayerId) {
    return { player_id: requireUUID(obj.player_id, `players[${index}].player_id`), tee_id }
  }

  // Validate guest_info
  const gi = obj.guest_info as Record<string, unknown>
  check(typeof gi === 'object' && gi !== null, `players[${index}].guest_info must be an object`)
  const display_name = requireString(gi.display_name, `players[${index}].guest_info.display_name`, 200)
  const handicap_index = requireNumber(gi.handicap_index, `players[${index}].guest_info.handicap_index`, -20, 80)
  const gender = gi.gender != null
    ? requireEnum(gi.gender, `players[${index}].guest_info.gender`, ['male', 'female'])
    : undefined

  return { tee_id, guest_info: { display_name, handicap_index, gender } }
}

export interface ValidatedTournamentPlayer {
  player_id?: string
  team_name?: string
  guest_info?: { display_name: string; handicap_index: number; gender?: string }
}

export function validateTournamentPlayer(p: unknown, index: number): ValidatedTournamentPlayer {
  check(typeof p === 'object' && p !== null, `players[${index}] must be an object`)
  const obj = p as Record<string, unknown>

  const hasPlayerId = obj.player_id != null && obj.player_id !== ''
  const hasGuestInfo = obj.guest_info != null

  check(hasPlayerId || hasGuestInfo, `players[${index}] must have player_id or guest_info`)

  const team_name = optionalString(obj.team_name, `players[${index}].team_name`, 200) ?? undefined

  if (hasPlayerId) {
    return { player_id: requireUUID(obj.player_id, `players[${index}].player_id`), team_name }
  }

  const gi = obj.guest_info as Record<string, unknown>
  check(typeof gi === 'object' && gi !== null, `players[${index}].guest_info must be an object`)
  const display_name = requireString(gi.display_name, `players[${index}].guest_info.display_name`, 200)
  const handicap_index = requireNumber(gi.handicap_index, `players[${index}].guest_info.handicap_index`, -20, 80)
  const gender = gi.gender != null
    ? requireEnum(gi.gender, `players[${index}].guest_info.gender`, ['male', 'female'])
    : undefined

  return { team_name, guest_info: { display_name, handicap_index, gender } }
}
