@echo off
setlocal
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
cd /d "%ROOT%\.cli"
start "" "UrhoXRuntime.exe" main.lua "-tapcode_dir=%ROOT%" -tool_mode -x 1280 -y 720
endlocal
