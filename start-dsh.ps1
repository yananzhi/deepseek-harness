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

# Node path from .env (node_path=...), fallback to default install.
$envNodePath = $null
if (Test-Path "$PSScriptRoot/.env") {
  Get-Content "$PSScriptRoot/.env" | Where-Object { $_ -match '^\s*node_path\s*=' } | ForEach-Object {
    $val = ($_ -split '=',2)[1].Trim().Trim('"').Trim("'").Trim()
    if ($val) { $env:node_path = $val; $envNodePath = $val }
  }
  if (-not $envNodePath) {
    Get-Content "$PSScriptRoot/.env" | Where-Object { $_ -match '^\s*NODE_PATH\s*=' } | ForEach-Object {
      $val = ($_ -split '=',2)[1].Trim().Trim('"').Trim("'").Trim()
      if ($val) { $env:node_path = $val; $envNodePath = $val }
    }
  }
}
if (-not $envNodePath) { $envNodePath = "C:\Program Files\nodejs" }
$env:PATH = "$envNodePath;$env:PATH"

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
