# Agent Note: 本机 Windows 开发机 Node 22 可用位置

Status: implemented

[English](2026-09-16-node22-local-availability.md) | 中文

## Problem

`pnpm run build` 与 `pnpm run test` 要求 `node ^22.19 || >=24`。`scripts/client-build-environment.ts:5` 从 `node:fs` 导入 `globSync`，该 API 仅在 Node 22 中提供，因此在 Node 20 上构建会以 `ERR_UNKNOWN_FILE_EXTENSION`/`globSync is not a function` 失败，且适配器测试会因缺少 `Promise.withResolvers` 失败。默认 `PATH` 上的 `node` 经 `C:\nvm4w\nodejs -> C:\Users\HONOR\AppData\Local\nvm\v20.19.1` 解析为 `v20.19.1`，而本机另有一份符合要求的 Node。之前未走代理的 `nvm install 22` 在 `registry.npmmirror.com`/`nodejs.org` 上超时。

## Decision

符合要求的 Node 已安装于 `C:\Program Files\nodejs\node.exe`（截至 2026-09-16 为 `v22.23.2`）。`start.bat:9` 与 `start-dsh.ps1:18` 已在启动时将该目录前置到 `PATH`（`set "PATH=C:\Program Files\nodejs;...`），因此经这些脚本启动的 `dsh --profile web|headless` 均在 Node 22 上运行，构建后即可包含每模型 `proxyUrl` 的前后端改动。`bash` 下手动执行 `pnpm` 时请使用 `PATH="/c/Program Files/nodejs:$PATH" pnpm ...` 或直接调用 `"/c/Program Files/nodejs/node.exe"`。本机出站代理位于 `127.0.0.1:18889`（见 `start-with-proxy.bat:9`）；后续如需 `nvm install` 或 `curl -L https://nodejs.org/dist/...`，必须走代理（`curl -x http://127.0.0.1:18889 ...` / `set HTTP_PROXY=...`），否则会超时。无需重复进行未走代理的下载。

## Alternatives considered

* **继续使用 `C:\nvm4w\nodejs`（20.19.1）并 polyfill `globSync`/`Promise.withResolvers`**：会掩盖 CI 强制的版本约束（`22.19 || >=24`），与线上工具链不一致。
* **不走代理的 `nvm install 22` 或直连 `https://nodejs.org/dist` 下载**：在本网络环境下已观察到超时；走代理的 `curl -x http://127.0.0.1:18889` 可成功，但既然二进制已存在则无需再次下载。
* **增加自动选择 Node 的 `pnpm` 垫片**：过度设计；`start.bat` 已处理启动时的 `PATH`，临时命令显式加 `PATH` 前缀更直接。

## Consequences

`pnpm run build` 必须在 `PATH` 含 Node 22 的情况下执行；`PATH="/c/Program Files/nodejs:$PATH" pnpm run build` 之后，`apps/web/dist` 与 `packages/*/lib/types` 均包含每模型 `proxyUrl` 特性，`start.bat web` 即可提供。`nvm list` 仍显示 `C:\nvm4w\nodejs` 指向 `v20.19.1`，该链接不是构建所用 Node。后续工作不应再尝试未走代理的 Node 下载，请直接使用 `C:\Program Files\nodejs` 下的二进制。
