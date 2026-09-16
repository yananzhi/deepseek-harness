/**
 * Per-request session routing headers every adapter sends outside model
 * input. Gateways that route or cache by conversation (notably OpenCode Go,
 * which documents `x-opencode-session` and returns `MissingSessionID`
 * without it) need the loop-stamped session on every chat request, on every
 * adapter — a header sent on only one adapter leaves the other paths
 * unroutable. The harness native `x-deepseek-harness-session-id` travels
 * alongside for gateways that recognize it.
 *
 * @module @deepseek-ai/dsh-llm/session-headers
 */

import type { Branded } from '@deepseek-ai/dsh-brand'

/** OpenCode Go's documented stable-conversation routing header. */
export const OPENCODE_SESSION_HEADER = 'x-opencode-session'

/** Harness native session header, already sent by the direct-fetch adapter. */
export const HARNESS_SESSION_HEADER = 'x-deepseek-harness-session-id'

/**
 * Build the session routing headers for one request. Header names are
 * lowercase (HTTP field names are case-insensitive on the wire).
 * @param sessionId - the loop-stamped session identity, if the caller carries one.
 * @returns both routing headers, or an empty object when the call has no session.
 */
export function sessionHeaders(
  sessionId: Branded<'SessionId'> | undefined,
): Record<string, string> {
  if (sessionId === undefined) return {}
  const value = String(sessionId)
  return {
    [OPENCODE_SESSION_HEADER]: value,
    [HARNESS_SESSION_HEADER]: value,
  }
}
