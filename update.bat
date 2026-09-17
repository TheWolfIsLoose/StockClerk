@echo off
REM Stock Clerk - one-click updater  [DEV ONLY, DO NOT SHIP]
REM
REM This file is a local dev convenience. It MUST NOT be included in
REM any packaged release uploaded to CurseForge, Wago, or WoWInterface.
REM The .pkgmeta ignore list excludes it from packaged builds.
REM
REM Usage:
REM   Double-click                 -> pull the branch named in .branch
REM                                   (or the currently checked-out branch
REM                                   if .branch is missing)
REM   update.bat wip/foo-branch    -> switch to that branch and pull it
REM                                   (also writes it into .branch so
REM                                   subsequent double-clicks stay on it)
REM
REM After it finishes, type /reload in WoW.

setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

echo ====================================================
echo   Stock Clerk - Updating from GitHub
echo ====================================================
echo.

REM ---- Resolve target branch ------------------------------------------
REM Priority: command-line arg  ->  .branch file  ->  current HEAD branch
set TARGET=
if not "%~1"=="" (
    set TARGET=%~1
) else if exist ".branch" (
    set /p TARGET=<.branch
)

if "%TARGET%"=="" (
    for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD') do set TARGET=%%b
)

REM Trim stray whitespace/CR from .branch file
for /f "tokens=* delims= " %%a in ("!TARGET!") do set TARGET=%%a
set TARGET=!TARGET: =!

REM ---- Switch branches if needed --------------------------------------
for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD') do set CURRENT=%%b

if /i not "!CURRENT!"=="!TARGET!" (
    echo Switching branch: !CURRENT! -^> !TARGET!
    git fetch origin
    if errorlevel 1 (
        echo *** git fetch failed. Check your network / auth.
        pause
        exit /b 1
    )
    git checkout !TARGET!
    if errorlevel 1 (
        echo.
        echo *** Checkout failed. If you have local edits, commit or
        echo *** stash them first, or make sure the branch name is
        echo *** spelled correctly (case-sensitive on some setups).
        echo.
        pause
        exit /b 1
    )
)

REM ---- Persist the branch choice --------------------------------------
REM Write .branch so the next double-click stays on this branch without
REM needing the argument again.
> .branch echo !TARGET!

REM ---- Show version before pull ---------------------------------------
for /f "delims=" %%h in ('git log -1 --format^=%%h') do set BEFORE=%%h

echo Pulling !TARGET!...
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
    echo Already up to date on !TARGET! at !AFTER!.
) else (
    echo Updated !TARGET!: !BEFORE!  -^>  !AFTER!
    echo.
    echo --- New commits ---
    git log --oneline !BEFORE!..!AFTER!
)

echo.
echo Done. Type /reload in WoW to load the new version.
echo.
pause
