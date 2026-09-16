@echo off
REM Stock Clerk - one-click updater
REM Double-click this file to pull the latest version from GitHub.
REM After it finishes, type /reload in WoW.

setlocal
cd /d "%~dp0"

echo ====================================================
echo   Stock Clerk - Updating from GitHub
echo ====================================================
echo.

REM Show current version before pulling
for /f "delims=" %%h in ('git log -1 --format^=%%h') do set BEFORE=%%h

git pull --ff-only
if errorlevel 1 (
    echo.
    echo *** Pull failed. If you have local edits, either commit
    echo *** them or use "git stash" before running this again.
    echo.
    pause
    exit /b 1
)

for /f "delims=" %%h in ('git log -1 --format^=%%h') do set AFTER=%%h

echo.
if "%BEFORE%"=="%AFTER%" (
    echo Already up to date at %AFTER%.
) else (
    echo Updated: %BEFORE%  -^>  %AFTER%
    echo.
    echo --- New commits ---
    git log --oneline %BEFORE%..%AFTER%
)

echo.
echo Done. Type /reload in WoW to load the new version.
echo.
pause
