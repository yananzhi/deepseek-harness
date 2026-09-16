@echo off
rem Start DeepSeek Harness with outbound proxy. Mirrors start.bat (which is left untouched).
rem Usage: start-with-proxy.bat [profile] [task-or-args...]   (default profile: web)
rem   start-with-proxy.bat web
rem   start-with-proxy.bat web --port 8080
rem   start-with-proxy.bat headless "run the tests"
setlocal
rem --- proxy (edit the port here if it changes) ---
set "HTTP_PROXY=http://127.0.0.1:18889"
set "HTTPS_PROXY=http://127.0.0.1:18889"
set "http_proxy=http://127.0.0.1:18889"
set "https_proxy=http://127.0.0.1:18889"
set "NO_PROXY=localhost,127.0.0.1"
set "no_proxy=localhost,127.0.0.1"
echo [proxy] HTTP_PROXY=%HTTP_PROXY% HTTPS_PROXY=%HTTPS_PROXY% NO_PROXY=%NO_PROXY%
rem --- same launch as start.bat below (node_path from .env, see .env_example) ---
if exist "%~dp0.env" for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%~dp0.env") do (
  if /i "%%a"=="node_path" set "node_path=%%b"
  if /i "%%a"=="NODE_PATH" set "node_path=%%b"
)
if not defined node_path set "node_path=C:\Program Files\nodejs"
for /f "tokens=* delims= " %%p in ("%node_path%") do set "node_path=%%p"
set "node_path=%node_path:"=%"
set "PATH=%node_path%;C:\Users\HONOR\bin;%PATH%"
cd /d "%~dp0"
set "PROFILE=%~1"
if "%PROFILE%"=="" set "PROFILE=web"
shift
if /i "%PROFILE%"=="headless" (
  if "%~1"=="" echo Usage: start-with-proxy.bat headless "task ..." & exit /b 2
)
where pnpm >nul 2>&1
if %errorlevel%==0 (
  pnpm dsh --profile %PROFILE% %1 %2 %3 %4 %5 %6 %7 %8 %9
) else (
  "C:\Users\HONOR\bin\pnpm.cmd" dsh --profile %PROFILE% %1 %2 %3 %4 %5 %6 %7 %8 %9
)
