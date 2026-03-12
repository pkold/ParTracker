/**
 * Simple in-memory rate limiter for Supabase Edge Functions.
 *
 * Uses a sliding-window counter per key (typically user ID or IP).
 * State lives in the Deno isolate's memory — it resets on cold start,
 * which is acceptable for burst-abuse protection.
 */

interface RateLimitEntry {
  timestamps: number[]
}

const store = new Map<string, RateLimitEntry>()

// Clean up stale entries every 60 seconds to prevent memory leaks
const CLEANUP_INTERVAL = 60_000
let lastCleanup = Date.now()

function cleanup(windowMs: number) {
  const now = Date.now()
  if (now - lastCleanup < CLEANUP_INTERVAL) return
  lastCleanup = now

  const cutoff = now - windowMs
  for (const [key, entry] of store) {
    entry.timestamps = entry.timestamps.filter((t) => t > cutoff)
    if (entry.timestamps.length === 0) store.delete(key)
  }
}

interface RateLimitOptions {
  /** Maximum requests allowed in the window. Default: 30 */
  maxRequests?: number
  /** Time window in milliseconds. Default: 60_000 (1 minute) */
  windowMs?: number
}

interface RateLimitResult {
  allowed: boolean
  remaining: number
  retryAfterMs?: number
}

/**
 * Check whether a request is allowed under the rate limit.
 *
 * @param key - Unique identifier (user ID, IP, etc.)
 * @param options - maxRequests and windowMs overrides
 * @returns { allowed, remaining, retryAfterMs? }
 */
export function checkRateLimit(
  key: string,
  options?: RateLimitOptions
): RateLimitResult {
  const maxRequests = options?.maxRequests ?? 30
  const windowMs = options?.windowMs ?? 60_000

  cleanup(windowMs)

  const now = Date.now()
  const cutoff = now - windowMs

  let entry = store.get(key)
  if (!entry) {
    entry = { timestamps: [] }
    store.set(key, entry)
  }

  // Remove timestamps outside the window
  entry.timestamps = entry.timestamps.filter((t) => t > cutoff)

  if (entry.timestamps.length >= maxRequests) {
    const oldestInWindow = entry.timestamps[0]
    const retryAfterMs = oldestInWindow + windowMs - now
    return { allowed: false, remaining: 0, retryAfterMs }
  }

  entry.timestamps.push(now)
  return { allowed: true, remaining: maxRequests - entry.timestamps.length }
}

/**
 * Returns a 429 Response when the rate limit is exceeded.
 */
export function rateLimitResponse(
  retryAfterMs: number,
  corsHeaders: Record<string, string>
): Response {
  return new Response(
    JSON.stringify({ error: 'Too many requests. Please try again later.' }),
    {
      status: 429,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json',
        'Retry-After': String(Math.ceil(retryAfterMs / 1000)),
      },
    }
  )
}
