@echo off
REM Stock Clerk - one-click updater  [DEV ONLY, DO NOT SHIP]
REM
REM Excluded from packaged releases via .pkgmeta (Dev/ is ignored).
REM
REM Hard-syncs the addon folder to a GitHub branch: main by default, or
REM `update.bat dev` for alpha builds. Local file changes are discarded
REM (edits happen on the dev workstation and come down through git).
REM SavedVariables live in WTF\, not here, so they are unaffected.
REM
REM Self-heals a zip / CurseForge install (no .git) into a git checkout.
REM Runs from a temp copy so git can rewrite this file mid-sync safely.
REM Type /reload in WoW when it finishes.

setlocal EnableExtensions

REM ---- Re-launch from %TEMP% (cmd reads .bat files as it runs them) ----
if not "%SC_UPDATE_TMP%"=="1" (
    set "SC_UPDATE_SELF=%~dp0"
    set "SC_UPDATE_TMP=1"
    copy /y "%~f0" "%TEMP%\stockclerk_update.bat" >nul
    call "%TEMP%\stockclerk_update.bat" %*
    exit /b
)

REM ---- Branch: default main; accept "origin/dev" as "dev" -------------
set "BRANCH=%~1"
if "%BRANCH%"=="" set "BRANCH=main"
if /i "%BRANCH:~0,7%"=="origin/" set "BRANCH=%BRANCH:~7%"

REM ---- Locate the addon root ------------------------------------------
set "ROOT=%SC_UPDATE_SELF%"
if not exist "%ROOT%StockClerk.toc" set "ROOT=%SC_UPDATE_SELF%..\"
if not exist "%ROOT%StockClerk.toc" (
    echo *** Could not find StockClerk.toc.
    echo *** This script must live at the addon root or in its Dev folder.
    pause
    exit /b 1
)
cd /d "%ROOT%"

echo ====================================================
echo   Stock Clerk - Sync to latest (%BRANCH%)
echo ====================================================
echo.

where git >nul 2>nul
if errorlevel 1 (
    echo *** Git is not installed or not on PATH. Get it from https://git-scm.com
    pause
    exit /b 1
)

REM ---- Self-heal: turn a zip / CurseForge install into a checkout -----
if not exist ".git" (
    echo This folder is not a git checkout, converting it into one...
    git init -q
    echo.
)
REM Always (re)point origin at the repo, in case it was missing or old.
git remote remove origin >nul 2>nul
git remote add origin https://github.com/TheWolfIsLoose/StockClerk.git

REM ---- Show current version -------------------------------------------
set "BEFORE="
for /f "delims=" %%h in ('git log -1 --format^=%%h 2^>nul') do set "BEFORE=%%h"
if "%BEFORE%"=="" (echo Current: none) else (echo Current: %BEFORE%)
echo.

REM ---- Fetch the branch -----------------------------------------------
echo Fetching %BRANCH% from GitHub...
git fetch origin %BRANCH%
if errorlevel 1 (
    echo *** git fetch failed. Check the branch name "%BRANCH%" and your network.
    pause
    exit /b 1
)

REM ---- Hard-sync: point a local branch of the same name at it --------
REM reset --hard discards local edits; clean -fd removes files git
REM doesn't know about (-f force, -d directories too).
git symbolic-ref HEAD refs/heads/%BRANCH%
git reset -q --hard FETCH_HEAD
if errorlevel 1 (
    echo *** git reset failed.
    pause
    exit /b 1
)
git clean -fdq

REM ---- Report ---------------------------------------------------------
for /f "delims=" %%h in ('git log -1 --format^=%%h') do set "AFTER=%%h"
echo.
if "%BEFORE%"=="" (
    echo Installed: %AFTER% on %BRANCH%
) else if "%BEFORE%"=="%AFTER%" (
    echo Already at %AFTER% on %BRANCH%. Nothing new.
) else (
    echo Updated: %BEFORE% -^> %AFTER% on %BRANCH%
    echo.
    echo --- New commits ---
    git log --oneline %BEFORE%..%AFTER% 2>nul
)
echo.
echo Done. Type /reload in WoW to load the new version.
echo.
pause
