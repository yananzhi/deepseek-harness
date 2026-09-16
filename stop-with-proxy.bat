@echo off
rem Stop DeepSeek Harness (proxy counterpart of stop.bat, which is left untouched).
rem Stopping only kills local node processes, so the proxy vars below are not
rem strictly needed; they are set for symmetry if stop-dsh.ps1 ever dials out.
rem Usage: stop-with-proxy.bat [profile] [force]   (no args stops everything)
rem   stop-with-proxy.bat
rem   stop-with-proxy.bat web
rem   stop-with-proxy.bat web force
setlocal
rem --- proxy (kept identical to start-with-proxy.bat) ---
set "HTTP_PROXY=http://127.0.0.1:18889"
set "HTTPS_PROXY=http://127.0.0.1:18889"
set "http_proxy=http://127.0.0.1:18889"
set "https_proxy=http://127.0.0.1:18889"
set "NO_PROXY=localhost,127.0.0.1"
set "no_proxy=localhost,127.0.0.1"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "PROFILE=%~1"
set "FORCE=%~2"
if "%PROFILE%"=="" (
  "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop-dsh.ps1"
) else if /i "%PROFILE%"=="force" (
  "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop-dsh.ps1" -Force
) else if /i "%FORCE%"=="force" (
  "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop-dsh.ps1" -Profile "%PROFILE%" -Force
) else (
  "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop-dsh.ps1" -Profile "%PROFILE%"
)
