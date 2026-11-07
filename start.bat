@echo off
cd /d "%~dp0"

set "AHK=%~dp0AutoHotkey64.exe"
if not exist "%AHK%" set "AHK=%~dp0v2\AutoHotkey64.exe"
if not exist "%AHK%" (
    echo AutoHotkey64.exe not found next to start.bat or in the v2 folder.
    pause
    exit /b 1
)

start "" "%AHK%" "%~dp0switch_cursor_monitor.ahk"
timeout /t 1 /nobreak >nul
start "" "%AHK%" "%~dp0switch_monitor.ahk"
start "" "%AHK%" "%~dp0switch_cursor_watchdog.ahk"
