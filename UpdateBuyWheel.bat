@echo off
setlocal EnableExtensions
title BuyWheel updater

rem ------------------------------------------------------------------------
rem  BuyWheel installer and updater.
rem  Double-click this file: it downloads the newest BuyWheel from GitHub and
rem  puts it into your World of Warcraft AddOns folder (replacing the old one).
rem  Your saved data (learned prices, settings) is not touched.
rem ------------------------------------------------------------------------

set "ZIP_URL=https://github.com/ByteMeTwice/BuyWheel/archive/refs/heads/main.zip"
set "WORK=%TEMP%\BuyWheelUpdate"
set "SAVED=%~dp0BuyWheel-AddOns-Path.txt"
set "ADDONS="

echo.
echo   BuyWheel updater
echo   ----------------
echo.

rem --- Is the game still running? The addon files are only read at startup, but it is
rem --- cleaner to update with the game closed.
tasklist /fi "imagename eq Wow.exe" 2>nul | find /i "Wow.exe" >nul
if not errorlevel 1 (
    echo   World of Warcraft seems to be running. Please close it first,
    echo   then press a key to continue.
    if not defined BW_TEST pause >nul
)

rem --- 1. Find the AddOns folder -------------------------------------------
if defined BW_ADDONS set "ADDONS=%BW_ADDONS%"
if defined ADDONS goto have_addons

if exist "%SAVED%" set /p ADDONS=<"%SAVED%"
if defined ADDONS if exist "%ADDONS%\" goto have_addons
set "ADDONS="

for %%L in (C D E F G H) do for %%P in (
    "%%L:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
    "%%L:\Program Files\World of Warcraft\_forever_\Interface\AddOns"
    "%%L:\World of Warcraft\_forever_\Interface\AddOns"
    "%%L:\Games\World of Warcraft\_forever_\Interface\AddOns"
) do if not defined ADDONS if exist "%%~P\" set "ADDONS=%%~P"
if defined ADDONS goto have_addons

echo   The AddOns folder was not found automatically.
echo   Open your World of Warcraft folder, go to  _forever_\Interface\AddOns
echo   and copy the folder path from the address bar. Paste it here.
echo.
set /p "ADDONS=  AddOns folder: "
set "ADDONS=%ADDONS:"=%"
if not defined ADDONS goto failed_path
if not exist "%ADDONS%\" goto failed_path

:have_addons
if not defined BW_ADDONS >"%SAVED%" echo %ADDONS%
echo   AddOns folder: %ADDONS%
echo.

rem --- Safety: never overwrite a development copy ---------------------------
if exist "%ADDONS%\BuyWheel\.git" goto failed_git

rem --- 2. Download ---------------------------------------------------------
if exist "%WORK%" rmdir /s /q "%WORK%"
mkdir "%WORK%"
echo   Downloading the newest version ...
if defined BW_ZIP (
    copy /y "%BW_ZIP%" "%WORK%\bw.zip" >nul
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri '%ZIP_URL%' -OutFile '%WORK%\bw.zip'"
)
if errorlevel 1 goto failed_download
if not exist "%WORK%\bw.zip" goto failed_download

rem --- 3. Unpack -----------------------------------------------------------
echo   Unpacking ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%WORK%\bw.zip' -DestinationPath '%WORK%\x' -Force"
if errorlevel 1 goto failed_unpack
set "SRC="
for /d %%D in ("%WORK%\x\*") do set "SRC=%%~fD"
if not defined SRC goto failed_unpack
if not exist "%SRC%\BuyWheel.toc" goto failed_unpack

rem --- 4. Replace the old version -------------------------------------------
echo   Installing ...
if exist "%ADDONS%\BuyWheel" rmdir /s /q "%ADDONS%\BuyWheel"
robocopy "%SRC%" "%ADDONS%\BuyWheel" /E /XD Tests docs .github /NFL /NDL /NJH /NJS /NP >nul
if errorlevel 8 goto failed_copy
if not exist "%ADDONS%\BuyWheel\BuyWheel.toc" goto failed_copy

set "VER=?"
for /f "tokens=3" %%V in ('findstr /b /c:"## Version:" "%ADDONS%\BuyWheel\BuyWheel.toc"') do set "VER=%%V"
rmdir /s /q "%WORK%" 2>nul

echo.
echo   Done. BuyWheel %VER% is installed.
echo   Start the game (or type /reload in the game) to use it.
echo.
goto end

:failed_path
echo.
echo   That folder does not exist. Run this file again and paste the path of
echo   the AddOns folder.
goto end

:failed_git
echo.
echo   %ADDONS%\BuyWheel is a Git copy (development version).
echo   Update it with "git pull" instead; this file does not touch it.
goto end

:failed_download
echo.
echo   The download failed. Check your internet connection and run this file again.
goto end

:failed_unpack
echo.
echo   The downloaded file could not be unpacked. Run this file again.
goto end

:failed_copy
echo.
echo   Installing failed. Close the game and run this file again.
goto end

:end
if not defined BW_TEST pause
endlocal
