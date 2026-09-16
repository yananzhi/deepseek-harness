# Agent Note: Local Node 22 availability on Windows dev machine

Status: implemented

English | [中文](2026-09-16-node22-local-availability.zh.md)

## Problem

`pnpm run build` and `pnpm run test` require `node ^22.19 || >=24`. `scripts/client-build-environment.ts:5` imports `globSync` from `node:fs`, which landed in Node 22, so a build on Node 20 fails with `ERR_UNKNOWN_FILE_EXTENSION`/`globSync is not a function` and `Promise.withResolvers` is missing for adapter tests. The default `node` on `PATH` resolves via `C:\nvm4w\nodejs -> C:\Users\HONOR\AppData\Local\nvm\v20.19.1` (`v20.19.1`), while a compliant Node is already present elsewhere. Prior attempts to `nvm install 22` without a proxy timed out on `registry.npmmirror.com`/`nodejs.org`.

## Decision

The compliant Node is already installed at `C:\Program Files\nodejs\node.exe` (`v22.23.2` as of 2026-09-16). `start.bat:9` and `start-dsh.ps1:18` already prepend that directory (`set "PATH=C:\Program Files\nodejs;...`), so `dsh --profile web|headless` launched via those scripts runs on Node 22 and includes per-model `proxyUrl` backend and frontend changes after a build. For manual `pnpm` from `bash`, run `PATH="/c/Program Files/nodejs:$PATH" pnpm ...` or invoke `"/c/Program Files/nodejs/node.exe"` directly. The local outbound proxy is at `127.0.0.1:18889` (`start-with-proxy.bat:9`); any future `nvm install` or `curl -L https://nodejs.org/dist/...` must be proxied (`curl -x http://127.0.0.1:18889 ...` / `set HTTP_PROXY=...`), otherwise it will time out. Do not re-attempt an unproxied download.

## Alternatives considered

* **Stay on `C:\nvm4w\nodejs` (20.19.1) and polyfill `globSync`/`Promise.withResolvers`**: hides the version contract that CI enforces (`22.19 || >=24`) and would diverge from the shipped toolchain.
* **Unproxied `nvm install 22` or direct `https://nodejs.org/dist` fetch**: observed to time out on this network; proxied `curl -x http://127.0.0.1:18889` succeeds, but the binary is already present so a download is unnecessary.
* **Add an auto-selecting `pnpm` shim**: overkill; `start.bat` already handles the launch PATH, and a one-line `PATH` prefix is explicit for ad-hoc commands.

## Consequences

`pnpm run build` must be run with Node 22 on `PATH`; after `PATH="/c/Program Files/nodejs:$PATH" pnpm run build` the `apps/web/dist` and `packages/*/lib/types` contain the per-model `proxyUrl` feature and `start.bat web` serves it. `nvm list` still shows `v20.19.1` as the `C:\nvm4w\nodejs` link; that link is not the build Node. Future work should not re-attempt an unproxied Node download; use the existing `C:\Program Files\nodejs` binary.
