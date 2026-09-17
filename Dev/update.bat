@echo off
REM Stock Clerk - one-click updater  [DEV ONLY, DO NOT SHIP]
REM
REM This file is a local dev convenience. It MUST NOT be included in
REM any packaged release uploaded to CurseForge, Wago, or WoWInterface.
REM The .pkgmeta ignore list excludes the entire Dev/ folder from
REM packaged builds.
REM
REM Usage: double-click. Pulls the latest from origin/main and then
REM tells you to /reload in WoW.
REM
REM Works whether the file lives at the addon root (legacy) or inside
REM Dev/ (current layout) -- resolves the addon root by looking for the
REM .toc file relative to this script's directory.

setlocal EnableExtensions EnableDelayedExpansion

REM ---- Locate the addon root ------------------------------------------
REM Try this script's directory first (legacy: update.bat at root).
REM If no .toc there, go up one level (current: update.bat in Dev/).
set ROOT=%~dp0
if not exist "%ROOT%StockClerk.toc" (
    set ROOT=%~dp0..\
)
if not exist "%ROOT%StockClerk.toc" (
    echo *** Could not find StockClerk.toc.
    echo *** This script must live at the addon root or one level below it.
    echo.
    pause
    exit /b 1
)
cd /d "%ROOT%"

echo ====================================================
echo   Stock Clerk - Updating from GitHub (main)
echo ====================================================
echo.

REM ---- Ensure we're on main -------------------------------------------
for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD') do set CURRENT=%%b
if /i not "!CURRENT!"=="main" (
    echo Currently on branch: !CURRENT!
    echo Switching to main...
    git fetch origin
    if errorlevel 1 (
        echo *** git fetch failed. Check your network / auth.
        pause
        exit /b 1
    )
    git checkout main
    if errorlevel 1 (
        echo.
        echo *** Checkout failed. If you have local edits, commit or
        echo *** stash them first.
        echo.
        pause
        exit /b 1
    )
)

REM ---- Show version before pull ---------------------------------------
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
if "!BEFORE!"=="!AFTER!" (
    echo Already up to date at !AFTER!.
) else (
    echo Updated: !BEFORE!  -^>  !AFTER!
    echo.
    echo --- New commits ---
    git log --oneline !BEFORE!..!AFTER!
)

echo.
echo Done. Type /reload in WoW to load the new version.
echo.
pause
