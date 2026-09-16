import { describe, expect, it } from 'vitest'
import { resolveAdapterOptions } from '../src/index.ts'

describe('llm-deepseek proxyUrl config', () => {
  it('accepts empty and whitespace as direct', () => {
    expect(resolveAdapterOptions({ proxyUrl: '' }).proxyUrl).toBeUndefined()
    expect(resolveAdapterOptions({ proxyUrl: '   ' }).proxyUrl).toBeUndefined()
    expect(resolveAdapterOptions({}).proxyUrl).toBeUndefined()
  })
  it('accepts a valid http proxy', () => {
    expect(resolveAdapterOptions({ proxyUrl: 'http://proxy.example:8080' }).proxyUrl).toBe('http://proxy.example:8080')
    expect(resolveAdapterOptions({ proxyUrl: ' https://proxy.example:8080 ' }).proxyUrl).toBe('https://proxy.example:8080')
  })
  it('rejects SOCKS and unsupported schemes', () => {
    expect(() => resolveAdapterOptions({ proxyUrl: 'socks5://proxy.example' })).toThrow(/SOCKS/)
    expect(() => resolveAdapterOptions({ proxyUrl: 'ftp://proxy.example' })).toThrow(/unsupported/)
  })
  it('rejects malformed URL', () => {
    expect(() => resolveAdapterOptions({ proxyUrl: 'not a url' })).toThrow(/not a valid URL/)
  })
  it('isolates per-route: one route proxied does not affect another resolution', () => {
    const a = resolveAdapterOptions({ proxyUrl: 'http://a.example:8080' })
    const b = resolveAdapterOptions({})
    expect(a.proxyUrl).toBe('http://a.example:8080')
    expect(b.proxyUrl).toBeUndefined()
  })
})
