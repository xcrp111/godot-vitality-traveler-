@echo off
setlocal
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"

if not exist "%ROOT%\.cli\UrhoXRuntime.exe" (
    echo.
    echo [ERROR] Missing .cli\UrhoXRuntime.exe
    echo Extract the UrhoXRuntime package into "%ROOT%\.cli\" first, then run this file again.
    echo.
    pause
    exit /b 1
)

rem The runtime requires .cli\ResCache to exist (shader cache); create it if missing.
if not exist "%ROOT%\.cli\ResCache" mkdir "%ROOT%\.cli\ResCache"

cd /d "%ROOT%\.cli"
start "" "UrhoXRuntime.exe" main.lua "-tapcode_dir=%ROOT%" -tool_mode -x 1280 -y 720
endlocal
