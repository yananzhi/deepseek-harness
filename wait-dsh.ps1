#Requires -Version 5.1
<#
.SYNOPSIS
  Wait for a detached dsh profile to print its ready URL, then report.
  Success prints the URL (it carries a per-boot token); failure prints tails.
  ASCII only: PowerShell 5.1 reads this file as ANSI, so non-ASCII would moji.
#>
param(
  [string]$Log = '',
  [string]$ErrLog = '',
  [int]$LauncherPid = 0,
  [int]$TimeoutSec = 300
)

$ErrorActionPreference = 'Stop'

$deadline = (Get-Date).AddSeconds($TimeoutSec)
$started = Get-Date
$url = $null
$fail = $null
while ((Get-Date) -lt $deadline) {
  if ($Log -ne '' -and (Test-Path $Log)) {
    $m = Select-String -Path $Log -Pattern 'dsh web: (http\S+)' | Select-Object -Last 1
    if ($m) { $url = $m.Matches[0].Groups[1].Value; break }
    if (Select-String -Path $Log -Pattern 'ELIFECYCLE' -Quiet) { $fail = 'profile process exited (see out.log)'; break }
  }
  if ($ErrLog -ne '' -and (Test-Path $ErrLog)) {
    if (Select-String -Path $ErrLog -Pattern '^Error' -Quiet) { $fail = 'error reported (see err log tail below)'; break }
  }
  if ($LauncherPid -gt 0 -and -not (Get-Process -Id $LauncherPid -ErrorAction SilentlyContinue)) {
    $fail = 'launcher exited before the service printed its URL (see err log tail below)'; break
  }
  $elapsed = [int]((Get-Date) - $started).TotalSeconds
  Write-Host ("`rwaiting for backend ... {0}s (timeout {1}s)" -f $elapsed, $TimeoutSec) -NoNewline
  Start-Sleep -Seconds 2
}
Write-Host ''
if ($url) {
  Write-Host "READY: $url"
  Write-Host 'Open that URL (it carries a per-boot token; the bare host:port answers 401).'
  Write-Host 'The service keeps running after this window closes.'
  exit 0
}
if (-not $fail) { $fail = 'timed out waiting for the ready URL' }
Write-Host "START FAILED: $fail"
if ($ErrLog -ne '' -and (Test-Path $ErrLog)) {
  Write-Host '--- err log tail ---'
  Get-Content $ErrLog | Select-Object -Last 15 | ForEach-Object { Write-Host $_ }
}
if ($Log -ne '' -and (Test-Path $Log)) {
  Write-Host '--- out log tail ---'
  Get-Content $Log | Select-Object -Last 8 | ForEach-Object { Write-Host $_ }
}
exit 1
