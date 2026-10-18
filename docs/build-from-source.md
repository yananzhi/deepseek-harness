# Build from source (local runbook)

English | [中文](build-from-source.zh.md)

This page records the install and build steps for this Windows machine only; the general contributor workflow is [development.md](development.md), and the test tiers are [testing.md](testing.md).

## Environment

Node comes from `C:\Program Files\nodejs` as 22.x; the PATH default of Node 20 makes the build fail or the service start silently dead. The launcher reads `node_dir` and `launch_*` from the repository root `.env`; proxy variables live in the Windows user environment, not in the repository `.env`.

## Install dependencies

The local outbound proxy (`127.0.0.1:18889`) throttles registry downloads to about 8 KB/s, too slow to finish a large package; the domestic mirrors reach MB/s over a direct connection (Tencent 1.3, npmmirror 3.2, Huawei 4.5), so installations bypass the proxy and name a mirror:

```sh
HTTP_PROXY= HTTPS_PROXY= http_proxy= https_proxy= NO_PROXY='*' pnpm install --registry https://registry.npmmirror.com
```

`minimumReleaseAgeExclude` in `pnpm-workspace.yaml` already exempts pi-ai and similar packages; when a supply-chain age check times out and rejects a package by mistake, append `--config.minimumReleaseAge=0`. `@deepseek-ai/libreoffice-kit-win32-x64` (117 MB, optional native package) does not download on this network; without `simple-icons` the client build misses a module, so install it into the store first.

## Build

```sh
pnpm run build
```

The artifacts are `apps/cli/lib/bin.js`, `apps/web/dist`, and each package's `lib/`. A changed area can be checked with `tsc -b <pkg>` and its `*.spec.ts` files before a full build.

## Run and verify

`start.bat` starts `node apps/cli/lib/bin.js --profile <launch_profile>` from the `launch_*` values in `.env`, and prints the ready URL (with a per-boot token) to `logs/dsh-<profile>.out.log`. Edits made directly inside `node_modules` are reverted by `pnpm install`, so restart the process after them.
