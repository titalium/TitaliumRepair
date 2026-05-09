@echo off
setlocal EnableDelayedExpansion

:: Verifie l'elevation
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if %errorlevel% NEQ 0 (
    echo.
    echo [*] elevation requise. Relance du script en mode administrateur...
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

cls
echo ===============================
echo ULTIMATE WINDOWS REPAIR TOOL
echo ===============================
echo.

:: [1] SFC
echo [1/13] Analyse avec SFC...
sfc /scannow
echo.

:: [2-4] DISM
echo [2/13] DISM - CheckHealth...
DISM /Online /Cleanup-Image /CheckHealth
echo.

echo [3/13] DISM - ScanHealth...
DISM /Online /Cleanup-Image /ScanHealth
echo.

echo [4/13] DISM - RestoreHealth...
DISM /Online /Cleanup-Image /RestoreHealth
echo.

:: [5] DISM - Component Store
echo [5/13] DISM - Verification du magasin de composants...
DISM /Online /Cleanup-Image /AnalyzeComponentStore
echo.

:: [6] Reenregistrement DLL
echo [6/13] Reenregistrement des DLL systeme...
for %%G in (
    "atl.dll" "urlmon.dll" "mshtml.dll" "shdocvw.dll" "browseui.dll"
    "jscript.dll" "vbscript.dll" "scrrun.dll" "msxml.dll" "msxml3.dll"
    "msxml6.dll" "actxprxy.dll" "softpub.dll" "wintrust.dll" "dssenh.dll"
    "rsaenh.dll" "gpkcsp.dll" "sccbase.dll" "slbcsp.dll" "cryptdlg.dll"
    "oleaut32.dll" "ole32.dll" "shell32.dll" "initpki.dll" "wuapi.dll"
    "wuaueng.dll" "wucltui.dll" "wups.dll" "wups2.dll" "wuweb.dll"
    "qmgr.dll" "qmgrprxy.dll" "wucltux.dll" "muweb.dll" "wuwebv.dll"
) do (
    regsvr32 /s %%G
)
echo OK.
echo.

:: [7] Reinitialiser Windows Update
echo [7/13] Reinitialisation de Windows Update...
net stop bits
net stop wuauserv
net stop appidsvc
net stop cryptsvc

del /f /s /q %windir%\SoftwareDistribution\*
del /f /s /q %windir%\System32\catroot2\*

net start bits
net start wuauserv
net start appidsvc
net start cryptsvc
echo OK.
echo.

:: [8] WMI
echo [8/13] Verification du WMI...
winmgmt /verifyrepository
if %errorlevel% NEQ 0 (
    echo [!] Detection d’un probleme WMI, tentative de reparation...
    winmgmt /salvagerepository
)
echo OK.
echo.

:: [9] Nettoyage fichiers temporaires
echo [9/13] Nettoyage du systeme...
del /f /s /q %temp%\*
del /f /s /q C:\Windows\Temp\*
cleanmgr /sagerun:1
echo.

:: [10] CHKDSK
echo [10/13] Verification du disque avec CHKDSK
set /p doChkdsk="Souhaitez-vous lancer CHKDSK au prochain redemarrage ? (O/N) : "
if /I "!doChkdsk!"=="O" (
    echo.
    echo Planification de CHKDSK...
    chkdsk C: /F /R
    echo CHKDSK sera execute au redemarrage.
) else (
    echo CHKDSK annule.
)
echo.

:: [11] Mises a jour Windows (manuelles)
echo [11/13] Recherche des mises a jour Windows...
powershell -Command "Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot"

:: OU version simple PowerShell sans PSWindowsUpdate :
echo Recherche et installation des mises a jour Windows...
powershell -Command "Get-WindowsUpdate; Install-WindowsUpdate -AcceptAll -IgnoreReboot"
echo.

:: [12] Mise a jour des pilotes via Windows Update
echo [12/13] Recherche et mise a jour des pilotes...
powershell -Command "Start-Process ms-settings:windowsupdate" 
echo (Verifie manuellement si tu veux forcer les pilotes depuis Windows Update UI)
echo.

:: [13] Winget - Mise a jour des logiciels
echo [13/13] Verification de winget...
where winget >nul 2>&1
if %errorlevel%==0 (
    echo Winget detecte. Mise a jour des logiciels installes...
    winget upgrade --all --silent --include-unknown
) else (
    echo Winget non detecte. Mise a jour des applis impossible.
)
echo.

echo ===============================
echo Toutes les operations sont terminees.
echo ===============================
pause
exit
