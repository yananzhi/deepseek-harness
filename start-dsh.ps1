#Requires -Version 5.1
<#
.SYNOPSIS
  Start DeepSeek Harness hidden, running the built CLI entry (apps/cli/lib/bin.js).

.DESCRIPTION
  Uses the published launch path directly - `node apps/cli/lib/bin.js --profile web`
  - with no pnpm and no tsx. Task Scheduler owns the process, started through a
  windowless wscript launcher, so it has no console window and is independent of
  this window or any launcher that ran it.

  Configuration comes from .env next to this script (see .env_example):
    node_dir, launch_profile, launch_port, launch_args, launch_timeout.
  Logs: logs\dsh-<profile>.out.log / .err.log. Stop with stop.bat.
#>
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# Self-elevate: Register/Start-ScheduledTask needs admin. When this script is
# run directly without elevation, re-launch elevated so callers don't have to
# right-click Run as administrator. (start.bat already elevates itself; this is
# the fallback for `powershell -File start-dsh.ps1`.)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host 'Requesting administrator privileges to register/start the scheduled task ...'
  try {
    Start-Process powershell.exe -Verb RunAs -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"")
  } catch {
    Write-Host 'Elevation was cancelled or failed; start aborted.'
    exit 1
  }
  exit 0
}

function Read-DotEnv([string]$path) {
  $map = @{}
  if (-not (Test-Path $path)) { return $map }
  foreach ($line in Get-Content $path) {
    if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
    $i = $line.IndexOf('=')
    $k = $line.Substring(0, $i).Trim().ToLowerInvariant()
    if (-not $k) { continue }
    $map[$k] = $line.Substring($i + 1).Trim().Trim('"').Trim("'")
  }
  return $map
}

# Single-quote a value for a PowerShell script literal.
function PsQuote([string]$v) { return "'" + ($v -replace "'", "''") + "'" }

$cfg = Read-DotEnv (Join-Path $root '.env')
$profile = if ($cfg['launch_profile']) { $cfg['launch_profile'] } else { 'web' }
$port = if ($cfg['launch_port'] -match '^\d+$') { $cfg['launch_port'] } else { '' }
$extra = if ($cfg['launch_args']) { $cfg['launch_args'] } else { '' }
$timeout = if ($cfg['launch_timeout'] -match '^\d+$') { [int]$cfg['launch_timeout'] } else { 300 }
$nodeDir = if ($cfg['node_dir']) { $cfg['node_dir'] } else { '' }

# The published CLI entry. It must be built once with `pnpm run build`.
$bin = Join-Path $root 'apps\cli\lib\bin.js'
if (-not (Test-Path $bin)) {
  Write-Host "missing $bin - run 'pnpm run build' once in this checkout, then retry"; exit 1
}

# Resolve node: .env node_dir wins over a stale node earlier on PATH; a major
# gate then fails loudly instead of launching a silent dead service.
if ($nodeDir -and (Test-Path (Join-Path $nodeDir 'node.exe'))) {
  $env:PATH = "$nodeDir;$env:PATH"
} elseif (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  if (Test-Path "$env:ProgramFiles\nodejs\node.exe") { $env:PATH = "$env:ProgramFiles\nodejs;$env:PATH" }
}
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) { Write-Host 'node not found: put it on PATH or set node_dir in .env'; exit 1 }
$node = $nodeCmd.Source
$major = [int]((& $node --version) -replace '^v', '' -split '\.')[0]
if ($major -lt 22) { Write-Host "node major $major is too old, this repo needs 22+: fix node_dir in .env"; exit 1 }

$logs = Join-Path $root 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$runner = Join-Path $logs "run-dsh-$profile.cmd"
$vbs = Join-Path $logs "run-dsh-$profile.vbs"
$outLog = Join-Path $logs "dsh-$profile.out.log"
$errLog = Join-Path $logs "dsh-$profile.err.log"
$taskName = "dsh-$profile"

# Every service argument, resolved here so no quoting has to survive the
# wscript/cmd/VBS escalation below.
$argStr = ' --profile ' + $profile
if ($port) { $argStr += ' --port ' + $port }
if ($extra) { $argStr += ' ' + $extra }

# Runner .cmd: fixes the working directory and sends output straight to files.
$runnerBody = "@echo off`r`ncd /d `"$root`"`r`n`"$node`" `"$bin`"$argStr > `"$outLog`" 2> `"$errLog`"`r`n"
Set-Content -Path $runner -Value $runnerBody -Encoding Ascii

# wscript is a GUI-subsystem host: it never opens a console, unlike
# `powershell -WindowStyle Hidden`, whose window Windows Terminal can still
# surface. Window style 0 keeps the runner and the node it spawns windowless.
$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
if (Test-Path $wscript) {
  $vbsText = 'CreateObject("WScript.Shell").Run """' + $runner + '""", 0, False'
  Set-Content -Path $vbs -Value $vbsText -Encoding Ascii
  $action = New-ScheduledTaskAction -Execute $wscript -WorkingDirectory $root -Argument ('//nologo "' + $vbs + '"')
} else {
  $psRunner = Join-Path $logs "run-dsh-$profile.ps1"
  $psArgs = '@(' + ((PsQuote $bin), (PsQuote '--profile'), (PsQuote $profile) -join ', ')
  if ($port) { $psArgs += ', ' + (PsQuote '--port') + ', ' + (PsQuote $port) }
  $psArgs += ')'
  $psBody = @"
`$env:PATH = $(PsQuote $(if ($nodeDir) { $nodeDir + ';' } else { '' })) + `$env:PATH
Start-Process -FilePath $(PsQuote $node) -ArgumentList $psArgs -WorkingDirectory $(PsQuote $root) -NoNewWindow -Wait -RedirectStandardOutput $(PsQuote $outLog) -RedirectStandardError $(PsQuote $errLog)
"@
  Set-Content -Path $psRunner -Value $psBody -Encoding Ascii
  $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -WorkingDirectory $root `
    -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $psRunner + '"')
}

# Replace any previous instance and clear stale logs so the wait below cannot
# read an old ready URL.
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Remove-Item $outLog, $errLog -Force -ErrorAction SilentlyContinue

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $taskName -Action $action -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Host "launched as scheduled task '$taskName' (no window); waiting for the backend ..."

& (Join-Path $root 'wait-dsh.ps1') -Log $outLog -ErrLog $errLog -LauncherPid 0 -TimeoutSec $timeout
exit $LASTEXITCODE
