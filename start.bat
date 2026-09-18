@echo off
rem DeepSeek Harness single launcher: spawns the service detached, then keeps
rem this window to watch the backend come up. Close it with any key once it
rem reports; the service keeps running.
rem Takes no arguments - everything lives in .env next to this file
rem (see .env_example):
rem   node_dir    - node install dir, e.g. C:\Program Files\nodejs
rem                 Wins over PATH when it holds a node.exe, so this pins
rem                 the Node major the repo requires (^22+) even when PATH
rem                 lists a stale Node first (below 22 the tsx entry exits
rem                 silently, which looks exactly like a dead service).
rem   launch_profile - profile to boot (default: web)
rem   launch_port    - optional --port value for the profile app
rem   launch_args    - optional extra args, space-separated, no single quotes
rem   launch_timeout - seconds to wait for the ready URL (default: 300)
rem No proxy here: DSH itself routes through the proxy named by the inherited
rem environment, so set HTTP_PROXY/HTTPS_PROXY once as Windows user
rem environment variables (or in $DSH_HOME/.env). The repo .env must NOT
rem hold proxy names - app-boot refuses to start when it does.
rem Usage: start.bat   (double-click it; close it with any key once ready)
rem The ready URL carries a per-boot token: open exactly that URL, because
rem the bare host:port answers 401 without it.
rem Logs: logs\dsh-<profile>.out.log and logs\dsh-<profile>.err.log
rem Stop: stop.bat [profile]
setlocal
cd /d "%~dp0"
rem --- config from .env (safe names only; never node_path/proxy) ---
set "NODE_DIR="
set "LAUNCH_PROFILE="
set "LAUNCH_PORT="
set "LAUNCH_ARGS="
set "LAUNCH_TIMEOUT="
if exist "%~dp0.env" for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%~dp0.env") do (
  if /i "%%a"=="node_dir" set "NODE_DIR=%%b"
  if /i "%%a"=="launch_profile" set "LAUNCH_PROFILE=%%b"
  if /i "%%a"=="launch_port" set "LAUNCH_PORT=%%b"
  if /i "%%a"=="launch_args" set "LAUNCH_ARGS=%%b"
  if /i "%%a"=="launch_timeout" set "LAUNCH_TIMEOUT=%%b"
)
for /f "tokens=* delims= " %%p in ("%NODE_DIR%") do set "NODE_DIR=%%p"
set "NODE_DIR=%NODE_DIR:"=%"
if defined LAUNCH_PROFILE for %%x in (%LAUNCH_PROFILE%) do set "LAUNCH_PROFILE=%%x"
if not defined LAUNCH_PROFILE set "LAUNCH_PROFILE=web"
if defined LAUNCH_PORT for %%x in (%LAUNCH_PORT%) do set "LAUNCH_PORT=%%x"
for /f "tokens=* delims= " %%p in ("%LAUNCH_ARGS%") do set "LAUNCH_ARGS=%%p"
if defined LAUNCH_TIMEOUT for %%x in (%LAUNCH_TIMEOUT%) do set "LAUNCH_TIMEOUT=%%x"
if not defined LAUNCH_TIMEOUT set "LAUNCH_TIMEOUT=300"
rem --- generic tool discovery (no hardcoded user/machine paths) ---
rem .env node_dir wins when it holds a node.exe, so a stale Node earlier on
rem PATH can never shadow the pinned one. A major-version gate then fails
rem loudly instead of launching a silent dead service.
if defined NODE_DIR (
  if exist "%NODE_DIR%\node.exe" set "PATH=%NODE_DIR%;%PATH%"
)
where node >nul 2>&1
if not %errorlevel%==0 (
  if exist "%ProgramFiles%\nodejs\node.exe" (
    set "PATH=%ProgramFiles%\nodejs;%PATH%"
  ) else (
    echo node not found: put it on PATH or set node_dir in .env & exit /b 1
  )
)
set "NODE_MAJOR="
for /f "tokens=2 delims=v." %%v in ('node --version 2^>nul') do set "NODE_MAJOR=%%v"
if not defined NODE_MAJOR echo cannot run node --version & exit /b 1
if %NODE_MAJOR% LSS 22 echo node major %NODE_MAJOR% too old, need 22+: fix node_dir in .env & exit /b 1
set "PNPM=pnpm"
where pnpm >nul 2>&1
if not %errorlevel%==0 (
  if exist "%USERPROFILE%\bin\pnpm.cmd" (
    set "PNPM=%USERPROFILE%\bin\pnpm.cmd"
  ) else (
    echo pnpm not found: neither on PATH nor at %%USERPROFILE%%\bin\pnpm.cmd & exit /b 1
  )
)
if not exist "logs" mkdir "logs"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "$extra = @(); if ('%LAUNCH_PORT%' -ne '') { $extra += '--port'; $extra += '%LAUNCH_PORT%' }; if ('%LAUNCH_ARGS%' -ne '') { $extra += '%LAUNCH_ARGS%'.Split(' ', [StringSplitOptions]::RemoveEmptyEntries) }; $p = Start-Process -FilePath '%PNPM%' -ArgumentList (@('dsh','--profile','%LAUNCH_PROFILE%') + $extra) -WorkingDirectory '%~dp0' -WindowStyle Hidden -RedirectStandardOutput 'logs\dsh-%LAUNCH_PROFILE%.out.log' -RedirectStandardError 'logs\dsh-%LAUNCH_PROFILE%.err.log' -PassThru; Set-Content -Path 'logs\dsh-%LAUNCH_PROFILE%.pid' -Value $p.Id"
echo launched, waiting for the backend to print its ready URL ...
set /p LAUNCH_PID=<"logs\dsh-%LAUNCH_PROFILE%.pid"
if not defined LAUNCH_PID set "LAUNCH_PID=0"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0wait-dsh.ps1" -Log "logs\dsh-%LAUNCH_PROFILE%.out.log" -ErrLog "logs\dsh-%LAUNCH_PROFILE%.err.log" -LauncherPid %LAUNCH_PID% -TimeoutSec %LAUNCH_TIMEOUT%
if errorlevel 1 (
  echo START FAILED - see above; full logs in logs\.
) else (
  echo Service is up - open the URL above.
)
echo Press any key to close this window; the service keeps running.
pause
