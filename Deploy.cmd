@echo off
rem Netrio Code DLP Deployer. Double-click to start. Keep this console window open while the deployer runs.
echo Starting the Code DLP Deployer. Keep this window open; it closes when the deployer closes.
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0scripts\Start-Deployer.ps1"
