const LOG_LEVEL = (Deno.env.get('LOG_LEVEL') || 'info').toLowerCase()

const LEVELS = { debug: 0, info: 1, warn: 2, error: 3 } as const
const current = LEVELS[LOG_LEVEL as keyof typeof LEVELS] ?? LEVELS.info

function shouldLog(level: keyof typeof LEVELS): boolean {
  return LEVELS[level] >= current
}

interface Logger {
  /** Verbose detail — player data, full payloads, calculations. Only in dev. */
  debug: (...args: unknown[]) => void
  /** Key operational events — "round created", counts. No PII. Safe for production. */
  info: (...args: unknown[]) => void
  /** Unexpected but recovered situations. */
  warn: (...args: unknown[]) => void
  /** Failures. Always logs. */
  error: (...args: unknown[]) => void
}

export function createLogger(name: string): Logger {
  const prefix = `[${name}]`
  return {
    debug: (...args) => { if (shouldLog('debug')) console.log(prefix, '[DEBUG]', ...args) },
    info:  (...args) => { if (shouldLog('info'))  console.log(prefix, '[INFO]', ...args) },
    warn:  (...args) => { if (shouldLog('warn'))  console.warn(prefix, '[WARN]', ...args) },
    error: (...args) => { if (shouldLog('error')) console.error(prefix, '[ERROR]', ...args) },
  }
}
