@echo off
rem ============================================================================
rem  GSI FLASH & SERVICE TOOL (launcher)
rem  Flash GSI, manage A/B slots, back up /data, service partitions.
rem
rem  Repository: https://codeberg.org/godflesh-77/gsi-tool
rem  Mirror:     https://github.com/godflesh-77/gsi-tool (read-only)
rem  License:    MIT
rem ============================================================================
chcp 65001 >nul
title GSI Flash Tool 1.1.0

set "PS1=%~dp0gsi-tool.ps1"

rem Prefer Windows Terminal (better resize, tabs, Unicode) if available.
where wt.exe >nul 2>&1
if %ERRORLEVEL% == 0 (
    wt.exe --size 120,40 powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
)

if %errorlevel% neq 0 (
    echo.
    echo Exit code: %errorlevel%
    pause
)
exit /b %errorlevel%
