@echo off
rem ===========================================================================
rem  Committee Manager - install on your Android phone over USB
rem  Double-click me, or run:  powershell -ExecutionPolicy Bypass -File "%~dp0install_on_phone.ps1"
rem ===========================================================================
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_on_phone.ps1"
set "CODE=%ERRORLEVEL%"
echo.
if not "%CODE%"=="0" (
    echo Script finished with error code %CODE%.
    echo Fix the reported problem, then run again.
) else (
    echo Done. See the instructions above to use the app.
)
echo.
pause
endlocal