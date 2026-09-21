@echo off
rem DeepSeek Harness launcher: starts the built CLI entry
rem   node apps/cli/lib/bin.js --profile <launch_profile>
rem in the background with no window. Takes no arguments - configuration lives
rem in .env next to this file (see .env_example): node_dir, launch_profile,
rem launch_port, launch_args, launch_timeout.
rem
rem The service is started through a windowless wscript launcher owned by Task
rem Scheduler, so no console window remains and closing this window - or the
rem launcher/shortcut that ran it - cannot stop the service.
rem Proxy settings do not belong here: DSH reads HTTP_PROXY/HTTPS_PROXY from the
rem inherited user environment (set them once with setx).
rem
rem Run `pnpm run build` once so apps/cli/lib/bin.js exists.
rem Logs: logs\dsh-<profile>.out.log / .err.log. Stop: stop.bat.
setlocal
cd /d "%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-dsh.ps1"
if errorlevel 1 (
  echo.
  echo START FAILED - see the message above.
  echo.
  pause
)
