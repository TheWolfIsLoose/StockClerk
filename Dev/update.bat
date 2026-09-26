@echo off
REM Stock Clerk - one-click updater  [DEV ONLY, DO NOT SHIP]
REM
REM Excluded from packaged releases via .pkgmeta (Dev/ is ignored).
REM
REM What this does: hard-syncs the local clone to origin/main.
REM Any local file changes are discarded (the user does not edit the
REM addon folder by hand -- edits happen on the dev workstation and
REM come down through git). SavedVariables live in WTF/, not here,
REM so they are unaffected.
REM
REM Double-click to run. Type /reload in WoW when it finishes.
REM
REM Works whether this file lives at the addon root (legacy) or inside
REM Dev/ (current layout). Finds the addon root by looking for
REM StockClerk.toc.

setlocal EnableExtensions

REM ---- Locate the addon root ------------------------------------------
set ROOT=%~dp0
if not exist "%ROOT%StockClerk.toc" set ROOT=%~dp0..\
if not exist "%ROOT%StockClerk.toc" (
    echo *** Could not find StockClerk.toc.
    echo *** This script must live at the addon root or one level below.
    pause
    exit /b 1
)
cd /d "%ROOT%"

REM ---- Self-heal: make sure this folder is a git checkout -------------
REM A CurseForge / zip install replaces the folder and drops .git; turn
REM it back into a clone in place instead of failing.
where git >nul 2>nul
if errorlevel 1 (
    echo *** Git is not installed or not on PATH. Install it from https://git-scm.com
    pause
    exit /b 1
)
if not exist ".git" (
    echo This folder is not a git checkout ^(zip or CurseForge install^).
    echo Converting it into one...
    git init -q
    git remote add origin https://github.com/TheWolfIsLoose/StockClerk.git
    echo.
)

echo ====================================================
echo   Stock Clerk - Sync to latest (origin/main)
echo ====================================================
echo.

REM ---- Show current version -------------------------------------------
set BEFORE=
for /f "delims=" %%h in ('git log -1 --format^=%%h 2^>nul') do set BEFORE=%%h
if "%BEFORE%"=="" (echo Current: none) else echo Current: %BEFORE%
echo.

REM ---- Fetch --------------------------------------------------------
echo Fetching from GitHub...
git fetch origin
if errorlevel 1 (
    echo *** git fetch failed. Check your network / auth.
    pause
    exit /b 1
)

REM ---- Hard-sync to origin/%BRANCH% ---------------------------------
REM checkout -f -B: discards any local edits and points a local branch of
REM                 the same name at origin/%BRANCH% (works on a fresh
REM                 init too, and keeps `git status` showing the branch).
REM clean -fd:   removes files git doesn't know about (e.g. old
REM              update.bat at root after it moved to Dev/).
REM             -f = force, -d = also directories.
echo Syncing to origin/%BRANCH%...
git checkout -q -f -B %BRANCH% origin/%BRANCH%
if errorlevel 1 (
    echo *** Sync failed. Does the branch "%BRANCH%" exist on GitHub?
    pause
    exit /b 1
)
git clean -fd
if errorlevel 1 (
    echo *** git clean failed.
    pause
    exit /b 1
)

REM ---- Report -------------------------------------------------------
for /f "delims=" %%h in ('git log -1 --format^=%%h') do set AFTER=%%h

echo.
if "%BEFORE%"=="" (
    echo Installed: %AFTER%  ^(%BRANCH%^)
) else if "%BEFORE%"=="%AFTER%" (
    echo Already at %AFTER%. Nothing new.
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
