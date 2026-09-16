@echo off
rem Start DeepSeek Harness from the already-built checkout. No checkout, no install.
rem Usage: start.bat [profile] [task-or-args...]   (default profile: web)
rem   start.bat web
rem   start.bat web --port 8080
rem   start.bat headless "run the tests"
setlocal
rem Load node_path from .env if present (see .env_example); fallback to default install path.
if exist "%~dp0.env" for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%~dp0.env") do (
  if /i "%%a"=="node_path" set "node_path=%%b"
  if /i "%%a"=="NODE_PATH" set "node_path=%%b"
)
if not defined node_path set "node_path=C:\Program Files\nodejs"
rem Trim surrounding spaces and quotes from node_path (handles "C:\Program Files\nodejs" and extra spaces)
for /f "tokens=* delims= " %%p in ("%node_path%") do set "node_path=%%p"
set "node_path=%node_path:"=%"
set "PATH=%node_path%;C:\Users\HONOR\bin;%PATH%"
cd /d "%~dp0"
set "PROFILE=%~1"
if "%PROFILE%"=="" set "PROFILE=web"
shift
if /i "%PROFILE%"=="headless" (
  if "%~1"=="" echo Usage: start.bat headless "task ..." & exit /b 2
)
where pnpm >nul 2>&1
if %errorlevel%==0 (
  pnpm dsh --profile %PROFILE% %1 %2 %3 %4 %5 %6 %7 %8 %9
) else (
  "C:\Users\HONOR\bin\pnpm.cmd" dsh --profile %PROFILE% %1 %2 %3 %4 %5 %6 %7 %8 %9
)
