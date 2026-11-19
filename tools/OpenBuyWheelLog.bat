@echo off
rem Opens the BuyWheel evaluation page and shows the saved-variables file(s) in Explorer.
setlocal
set "HERE=%~dp0"
start "" "%HERE%BuyWheelLog.html"
for /r "%HERE%..\..\..\..\WTF\Account" %%F in (BuyWheel.lua) do if exist "%%F" explorer /select,"%%~fF"
endlocal
