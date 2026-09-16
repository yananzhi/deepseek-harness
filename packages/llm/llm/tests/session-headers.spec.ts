import { describe, expect, it } from 'vitest'
import { brandString } from '@deepseek-ai/dsh-brand'
import {
  HARNESS_SESSION_HEADER,
  OPENCODE_SESSION_HEADER,
  sessionHeaders,
} from '@deepseek-ai/dsh-llm'

describe('sessionHeaders', () => {
  it('sends nothing when the call carries no session', () => {
    expect(sessionHeaders(undefined)).toEqual({})
  })

  it('sends both the gateway-documented and the native routing header', () => {
    expect(sessionHeaders(brandString('child-session'))).toEqual({
      [OPENCODE_SESSION_HEADER]: 'child-session',
      [HARNESS_SESSION_HEADER]: 'child-session',
    })
  })

  it('names the exact wire headers gateways match on', () => {
    expect(OPENCODE_SESSION_HEADER).toBe('x-opencode-session')
    expect(HARNESS_SESSION_HEADER).toBe('x-deepseek-harness-session-id')
  })
})
