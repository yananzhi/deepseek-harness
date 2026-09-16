import { describe, expect, it, vi } from 'vitest'
import { normalizeProxyUrl, isSupportedProxyUrl } from '../src/policy.ts'
import { fetchForProxyDispatcher } from '../src/install.ts'

vi.mock('undici', async (importOriginal) => {
  const mod = await importOriginal() as Record<string, unknown>
  return {
    ...(mod as object),
    fetch: vi.fn(async () => new Response('ok')),
  }
})

describe('normalizeProxyUrl', () => {
  it('treats absent, empty, and whitespace as direct', () => {
    expect(normalizeProxyUrl(undefined)).toBeUndefined()
    expect(normalizeProxyUrl('')).toBeUndefined()
    expect(normalizeProxyUrl('   ')).toBeUndefined()
    expect(normalizeProxyUrl('\t\n')).toBeUndefined()
  })
  it('trims and keeps a valid http proxy', () => {
    expect(normalizeProxyUrl(' http://proxy.example:8080 ')).toBe('http://proxy.example:8080')
    expect(normalizeProxyUrl('https://proxy.example:8080')).toBe('https://proxy.example:8080')
  })
  it('rejects SOCKS', () => {
    expect(() => normalizeProxyUrl('socks5://proxy.example')).toThrow(/SOCKS/)
    expect(() => normalizeProxyUrl('socks://proxy.example')).toThrow(/SOCKS/)
  })
  it('rejects unsupported scheme', () => {
    expect(() => normalizeProxyUrl('ftp://proxy.example')).toThrow(/unsupported/)
  })
  it('rejects malformed URL', () => {
    expect(() => normalizeProxyUrl('http://')).toThrow(/not a valid URL/)
    expect(() => normalizeProxyUrl('not a url')).toThrow(/not a valid URL/)
  })
  it('keeps isSupportedProxyUrl consistent', () => {
    expect(isSupportedProxyUrl('http://proxy.example')).toBe(true)
    expect(isSupportedProxyUrl('https://proxy.example')).toBe(true)
    expect(isSupportedProxyUrl('socks5://proxy.example')).toBe(false)
    expect(isSupportedProxyUrl('ftp://proxy.example')).toBe(false)
    expect(isSupportedProxyUrl('not a url')).toBe(false)
  })
})

describe('fetchForProxyDispatcher', () => {
  it('returns undefined for a direct route', () => {
    expect(fetchForProxyDispatcher(undefined)).toBeUndefined()
  })
  it('bypasses loopback and proxies everything else via undici fetch', async () => {
    const fakeDispatcher = { close: async () => {} } as unknown as import('undici').Dispatcher
    const fetchProxy = fetchForProxyDispatcher(fakeDispatcher)!
    const globalFetch = vi.fn(async () => new Response('ok'))
    vi.stubGlobal('fetch', globalFetch)
    const undici = await import('undici')
    const undiciFetch = undici.fetch as unknown as ReturnType<typeof vi.fn>
    try {
      await fetchProxy('http://example.com/api', { method: 'GET' })
      expect(undiciFetch).toHaveBeenCalledWith('http://example.com/api', expect.objectContaining({ dispatcher: fakeDispatcher }))
      expect(globalFetch).not.toHaveBeenCalled()
      vi.mocked(undiciFetch).mockClear()
      globalFetch.mockClear()
      await fetchProxy('http://localhost:3000/api', { method: 'GET' })
      expect(globalFetch).toHaveBeenCalledWith('http://localhost:3000/api', { method: 'GET' })
      expect(undiciFetch).not.toHaveBeenCalledWith('http://localhost:3000/api', expect.anything())
    } finally {
      vi.unstubAllGlobals()
      vi.mocked(undiciFetch).mockClear()
    }
  })
})
