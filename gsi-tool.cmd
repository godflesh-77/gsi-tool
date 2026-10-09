@echo off
chcp 65001 >nul
title GSI Flash Tool 0.9.9
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gsi-tool.ps1" %*
if %errorlevel% neq 0 (
    echo.
    echo Exit code: %errorlevel%
    pause
)
exit /b %errorlevel%
