@echo off
cd /d "%~dp0"

start "" "%~dp0AutoHotkey64.exe" "%~dp0switch_cursor_monitor.ahk"
timeout /t 1 /nobreak >nul
start "" "%~dp0AutoHotkey64.exe" "%~dp0switch_monitor.ahk"
start "" "%~dp0AutoHotkey64.exe" "%~dp0switch_cursor_watchdog.ahk"
