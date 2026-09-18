#Requires -Version 5.1
<#
.SYNOPSIS
  Start DeepSeek Harness from the already-built checkout. No checkout, no install.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\start-dsh.ps1 -Profile web
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\start-dsh.ps1 -Profile headless -Task "run the tests"
#>
param(
  [string]$Profile = 'headless',
  [string]$Task = ''
)

$ErrorActionPreference = 'Stop'

# Node discovery: prefer node on PATH; else node_dir=... from .env (see
# .env_example); else the default install location. Never node_path/NODE_PATH:
# app-boot rejects that name in any .env file, and exporting it would perturb
# Node module resolution for the child process.
$NodeDir = $null
if (Test-Path "$PSScriptRoot/.env") {
  Get-Content "$PSScriptRoot/.env" | Where-Object { $_ -match '^\s*node_dir\s*=' } | ForEach-Object {
    $val = ($_ -split '=',2)[1].Trim().Trim('"').Trim("'").Trim()
    if ($val) { $NodeDir = $val }
  }
}
if (-not $NodeDir) {
  try { $NodeDir = Split-Path (Get-Command node -ErrorAction Stop).Source } catch {}
}
if (-not $NodeDir) { $NodeDir = Join-Path $env:ProgramFiles 'nodejs' }
$env:PATH = "$NodeDir;$env:PATH"
# Major-version gate: below 22 the tsx entry exits silently, which looks
# exactly like a dead service. Fail loudly instead.
$NodeMajor = (& node --version) -replace '^v', '' -split '\.' | Select-Object -First 1
if ([int]$NodeMajor -lt 22) { throw "node major $NodeMajor too old, need 22+: fix node_dir in .env" }

# pnpm shim by absolute path: some terminals never picked up the PATH entry.
$PnpmCmd = 'C:\Users\HONOR\bin\pnpm.cmd'
if (-not (Test-Path $PnpmCmd)) { $PnpmCmd = 'pnpm' }
# Prefer pnpm on PATH if available (other machine, other user, corepack)
try { $p = Get-Command pnpm -ErrorAction Stop; $PnpmCmd = $p.Source } catch {}

Set-Location $PSScriptRoot

if ($Profile -eq 'headless' -and [string]::IsNullOrWhiteSpace($Task)) {
  throw 'headless needs -Task "..."'
}
if ([string]::IsNullOrWhiteSpace($Task)) {
  & $PnpmCmd dsh --profile $Profile
} else {
  & $PnpmCmd dsh --profile $Profile $Task
}
