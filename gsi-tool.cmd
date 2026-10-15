@echo off
rem ============================================================================
rem  GSI FLASH & SERVICE TOOL 1.0.3 (launcher)
rem  Flash GSI, manage A/B slots, back up /data, service partitions.
rem
rem  Repository: https://codeberg.org/godflesh-77/gsi-tool
rem  Mirror:     https://github.com/godflesh-77/gsi-tool (read-only)
rem  License:    MIT
rem ============================================================================
chcp 65001 >nul
title GSI Flash Tool 1.0.3
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gsi-tool.ps1" %*
if %errorlevel% neq 0 (
    echo.
    echo Exit code: %errorlevel%
    pause
)
exit /b %errorlevel%
