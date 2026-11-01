@echo off
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

schtasks /create /tn "MonitorSwitchAHK" /tr "\"%~dp0start.bat\"" /sc onlogon /rl highest /f
echo.
echo Autostart task "MonitorSwitchAHK" created.
pause
