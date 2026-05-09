@echo off
:: =============================================================================
::  TITALIUM REPAIR TOOL - Launcher (mode developpement)
::  Auteur : Titalium
::  Lance TitaliumRepair.ps1 avec auto-elevation et bypass d'execution policy.
::  Pour la version portable .exe, utilise Build-Exe.ps1.
:: =============================================================================

:: Verifie l'elevation (relance en admin si necessaire)
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if %errorlevel% NEQ 0 (
    echo [*] Elevation requise. Demande UAC...
    powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Lance le script PowerShell en STA (requis pour WPF) avec bypass policy
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0TitaliumRepair.ps1"

exit /b %errorlevel%
