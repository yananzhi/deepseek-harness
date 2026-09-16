import { describe, expect, it } from 'vitest'
import { resolveProfiles } from '../src/config.ts'

describe('llm-pi-ai proxyUrl per route', () => {
  it('accepts empty and whitespace as direct', () => {
    const m = resolveProfiles({
      a: { baseURL: 'https://a.example/v1', api: 'openai-completions', models: [{ id: 'm' }], proxyUrl: '' },
      b: { baseURL: 'https://b.example/v1', api: 'openai-completions', models: [{ id: 'm' }], proxyUrl: '   ' },
      c: { baseURL: 'https://c.example/v1', api: 'openai-completions', models: [{ id: 'm' }] },
    })
    expect(m.get('a')?.proxyUrl).toBeUndefined()
    expect(m.get('b')?.proxyUrl).toBeUndefined()
    expect(m.get('c')?.proxyUrl).toBeUndefined()
  })
  it('keeps a valid proxy per route and isolates', () => {
    const m = resolveProfiles({
      withProxy: { baseURL: 'https://a.example/v1', api: 'openai-completions', models: [{ id: 'm' }], proxyUrl: 'http://proxy.example:8080' },
      withoutProxy: { baseURL: 'https://b.example/v1', api: 'openai-completions', models: [{ id: 'm' }] },
    })
    expect(m.get('withProxy')?.proxyUrl).toBe('http://proxy.example:8080')
    expect(m.get('withoutProxy')?.proxyUrl).toBeUndefined()
  })
  it('trims surrounding whitespace', () => {
    const m = resolveProfiles({
      p: { baseURL: 'https://a.example/v1', api: 'openai-completions', models: [{ id: 'm' }], proxyUrl: ' https://proxy.example:8080 ' },
    })
    expect(m.get('p')?.proxyUrl).toBe('https://proxy.example:8080')
  })
  it('rejects SOCKS and unsupported schemes per route', () => {
    expect(() => resolveProfiles({
      bad: { baseURL: 'https://a.example/v1', api: 'openai-completions', models: [{ id: 'm' }], proxyUrl: 'socks5://proxy.example' },
    })).toThrow(/SOCKS/)
    expect(() => resolveProfiles({
      bad: { baseURL: 'https://a.example/v1', api: 'openai-completions', models: [{ id: 'm' }], proxyUrl: 'ftp://proxy.example' },
    })).toThrow(/unsupported/)
  })
  it('rejects malformed URL per route', () => {
    expect(() => resolveProfiles({
      bad: { baseURL: 'https://a.example/v1', api: 'openai-completions', models: [{ id: 'm' }], proxyUrl: 'not a url' },
    })).toThrow(/not a valid URL/)
  })
})
