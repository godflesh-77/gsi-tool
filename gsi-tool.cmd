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
title GSI Flash Tool 1.1.2

set "PS1=%~dp0gsi-tool.ps1"

rem Prefer Windows Terminal (better resize, tabs, Unicode) if available.
where wt.exe >nul 2>&1
if not errorlevel 1 (
    wt.exe --size 120,40 powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
    exit /b 0
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"
if %RC% neq 0 (
    echo.
    echo Exit code: %RC%
    pause
)
exit /b %RC%
