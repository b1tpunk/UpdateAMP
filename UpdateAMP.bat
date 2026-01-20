@echo off
setlocal EnableExtensions

rem ============================================================
rem UpdateAMP.bat
rem Updates AMP (via MSI) and then upgrades AMP instances/modules.
rem Defaults to instance ADS01 if no parameter is provided.
rem Runs safely with logging, validation, and consistent control.
rem ============================================================

rem ---- Config / Defaults ----
set "REBOOT_REQUIRED="
set "INSTANCE=%~1"
if not defined INSTANCE set "INSTANCE=ADS01"
if /i "%INSTANCE:~0,4%"=="AMP-" set "INSTANCE=%INSTANCE:~4%"

set "SERVICE=AMP-%INSTANCE%"
set "MSI_URL=https://cdn-downloads.c7rs.com/AMP/Mainline/AMPSetup.msi"
set "WORKDIR=%~dp0"
set "MSI_FILE=%WORKDIR%AMPSetup.msi"
set "LOGDIR=%WORKDIR%logs"

if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1

set "LOCKFILE=%LOGDIR%\UpdateAMP.lock"
if exist "%LOCKFILE%" (
  echo Another UpdateAMP run is already in progress. Lock file exists:
  echo   %LOCKFILE%
  exit /b 2
)
echo %DATE% %TIME% > "%LOCKFILE%"

rem Timestamp: YYYYMMDD-HHMMSS (locale-safe-ish)
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "TS=%%i"
set "LOGFILE=%LOGDIR%\UpdateAMP-%INSTANCE%-%TS%.log"

call :log "=== UpdateAMP starting ==="
call :log "Instance: %INSTANCE%"
call :log "Service : %SERVICE%"
call :log "MSI     : %MSI_FILE%"
call :log "Log     : %LOGFILE%"
echo.

rem ---- Confirm ----
echo This will stop AMP instances (all) and stop %SERVICE% if present/running.
set /p "answer=Continue? (Y/n): "
if /i "%answer%"=="n" (
  call :log "User aborted at first prompt."
  echo Aborting.
  del "%LOCKFILE%" >nul 2>&1
  exit /b 0
)

rem ---- Stop AMP instances (broad; safest before MSI update) ----
call :log "Stopping all AMP instances via ampinstmgr stopall..."
ampinstmgr stopall >> "%LOGFILE%" 2>&1
if errorlevel 1 (
  call :log "WARNING: ampinstmgr stopall returned errorlevel %errorlevel%."
)

rem ---- Stop ADS service if it exists and is running ----
call :service_exists "%SERVICE%"
if "%SERVICE_EXISTS%"=="1" (
  call :service_is_running "%SERVICE%"
  if "%SERVICE_RUNNING%"=="1" (
    call :log "Stopping service %SERVICE%..."
    net stop "%SERVICE%" >> "%LOGFILE%" 2>&1
    if errorlevel 1 (
      call :log "ERROR: Failed to stop service %SERVICE% (errorlevel %errorlevel%)."
      echo Failed to stop service %SERVICE%. See log:
      echo   %LOGFILE%
      del "%LOCKFILE%" >nul 2>&1
      exit /b 1
    )
  ) else (
    call :log "Service %SERVICE% exists but is not running."
  )
) else (
  call :log "Service %SERVICE% does not exist (will control instance via ampinstmgr)."
)

echo.
echo A new AMP installer will now be downloaded and installed.
echo Then AMP instances/modules will be upgraded.
set /p "answer=Continue? (Y/n): "
if /i "%answer%"=="n" (
  call :log "User aborted at second prompt. Attempting to restore startup state."
  call :restore
  echo Aborted. Restored what could be restored. See log:
  echo   %LOGFILE%
  del "%LOCKFILE%" >nul 2>&1
  exit /b 0
)

rem ---- Download MSI ----
call :log "Downloading AMP MSI from %MSI_URL% ..."
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$uri='%MSI_URL%'; $out='%MSI_FILE%'; $log='%LOGFILE%';" ^
  "function Write-Both([string]$m){ Write-Host $m; Add-Content -Path $log -Value ('['+(Get-Date -Format 'MM/dd/yy HH:mm:ss.fff')+'] '+$m) }" ^
  "try {" ^
  "  $req=[System.Net.HttpWebRequest]::Create($uri);" ^
  "  $resp=$req.GetResponse();" ^
  "  $total=$resp.ContentLength;" ^
  "  $in=$resp.GetResponseStream();" ^
  "  $fs=[System.IO.File]::Open($out,[System.IO.FileMode]::Create,[System.IO.FileAccess]::Write,[System.IO.FileShare]::None);" ^
  "  $buf=New-Object byte[] 1048576; $done=0L; $last=-1;" ^
  "  while(($read=$in.Read($buf,0,$buf.Length)) -gt 0){" ^
  "    $fs.Write($buf,0,$read); $done+=$read;" ^
  "    if($total -gt 0){" ^
  "      $pct=[int](($done*100)/$total);" ^
  "      if($pct -ne $last){" ^
  "        $mbDone=[math]::Round($done/1MB,1);" ^
  "        $mbTot=[math]::Round($total/1MB,1);" ^
  "        Write-Both ('Downloading: {0} MB / {1} MB ({2}%%)' -f $mbDone,$mbTot,$pct);" ^
  "        $last=$pct" ^
  "      }" ^
  "    } else {" ^
  "      $mbDone=[math]::Round($done/1MB,1);" ^
  "      Write-Both ('Downloading: {0} MB' -f $mbDone);" ^
  "    }" ^
  "  }" ^
  "  $fs.Close(); $in.Close(); $resp.Close();" ^
  "  Write-Both 'Finished.';" ^
  "} catch { Write-Both ('ERROR: Download failed: ' + $_.Exception.Message); exit 1 }"

if errorlevel 1 (
  call :log "ERROR: MSI download failed (errorlevel %errorlevel%)."
  echo Download failed. See log:
  echo   %LOGFILE%
  call :restore
  del "%LOCKFILE%" >nul 2>&1
  exit /b 1
)

if not exist "%MSI_FILE%" (
  call :log "ERROR: MSI file not found after download: %MSI_FILE%"
  echo Download did not produce MSI file. See log:
  echo   %LOGFILE%
  call :restore
  del "%LOCKFILE%" >nul 2>&1
  exit /b 1
)

call :log "Download complete."

rem ---- Install MSI (silent + log) ----
set "MSIINSTALLLOG=%LOGDIR%\AMPInstall-%TS%.log"
call :log "Running MSI install (silent). Installer log: %MSIINSTALLLOG%"

msiexec /i "%MSI_FILE%" /qn /norestart /l*v "%MSIINSTALLLOG%" >> "%LOGFILE%" 2>&1
set "MSI_RC=%ERRORLEVEL%"

if "%MSI_RC%"=="3010" goto :msi_ok_reboot
if "%MSI_RC%"=="0" goto :msi_ok
goto :msi_fail

:msi_ok_reboot
call :log "MSI install succeeded but requires reboot (3010). Continuing."
set "REBOOT_REQUIRED=1"
goto :msi_done

:msi_ok
call :log "MSI install completed successfully."
goto :msi_done

:msi_fail
call :log "ERROR: msiexec returned %MSI_RC%."
echo MSI install failed (code %MSI_RC%). See logs:
echo   %MSIINSTALLLOG%
echo   %LOGFILE%
call :restore
del "%LOCKFILE%" >nul 2>&1
exit /b %MSI_RC%

:msi_done

rem ---- Determine if Windows Server (ProductType != 1) ----
for /f %%i in ('powershell -NoProfile -Command "((Get-CimInstance -ClassName Win32_OperatingSystem).ProductType)"') do set "ProductType=%%i"
call :log "OS ProductType: %ProductType% (1=Workstation; !=1=Server/Domain Controller)"

rem ---- Upgrade instances/modules ----
rem Use ampinstmgr upgradeall (broad). On Server, elevate because AMP/ADS often needs admin.
if "%ProductType%"=="1" (
  call :log "Upgrading AMP instances/modules via: ampinstmgr upgradeall"
  ampinstmgr upgradeall >> "%LOGFILE%" 2>&1
  if errorlevel 1 (
    call :log "ERROR: ampinstmgr upgradeall failed (errorlevel %errorlevel%)."
    echo Upgrade failed. See log:
    echo   %LOGFILE%
    call :restore
    del "%LOCKFILE%" >nul 2>&1
    exit /b 1
  )
) else (
  call :log "Upgrading AMP instances/modules elevated (UAC): ampinstmgr upgradeall"
  powershell -NoProfile -Command ^
    "$p = Start-Process -FilePath 'ampinstmgr' -ArgumentList 'upgradeall' -Verb RunAs -Wait -PassThru; exit $p.ExitCode" >> "%LOGFILE%" 2>&1
  if errorlevel 1 (
    call :log "ERROR: Elevated upgradeall failed or was cancelled (errorlevel %errorlevel%)."
    echo Elevated upgrade failed or was cancelled. See log:
    echo   %LOGFILE%
    call :restore
    del "%LOCKFILE%" >nul 2>&1
    exit /b 1
  )
)

call :log "Upgrade step completed."

rem ---- Start ADS (service if exists; else instance) ----
call :log "Starting %INSTANCE%..."
call :service_exists "%SERVICE%"
if "%SERVICE_EXISTS%"=="1" (
  call :log "Starting service %SERVICE%..."
  net start "%SERVICE%" >> "%LOGFILE%" 2>&1
  if errorlevel 1 (
    call :log "ERROR: Failed to start service %SERVICE% (errorlevel %errorlevel%)."
    echo Failed to start service %SERVICE%. See log:
    echo   %LOGFILE%
    del "%LOCKFILE%" >nul 2>&1
    exit /b 1
  )
) else (
  call :log "Starting instance via ampinstmgr: %INSTANCE%"
  ampinstmgr start "%INSTANCE%" >> "%LOGFILE%" 2>&1
  if errorlevel 1 (
    call :log "ERROR: Failed to start instance %INSTANCE% (errorlevel %errorlevel%)."
    echo Failed to start instance %INSTANCE%. See log:
    echo   %LOGFILE%
    del "%LOCKFILE%" >nul 2>&1
    exit /b 1
  )
)

if defined REBOOT_REQUIRED (
  call :log "NOTE: Reboot is required to fully apply AMP Instance Manager updates."
  echo NOTE: A reboot is required to fully apply AMP Instance Manager updates.
)

call :log "=== UpdateAMP completed successfully ==="
echo.
echo AMP updated and upgradeall complete.
echo Log:
echo   %LOGFILE%
echo Installer log:
echo   %MSIINSTALLLOG%
echo.
echo Log in to AMP and click "Update All" to update Generic module instances/configs as needed.
del "%LOCKFILE%" >nul 2>&1
exit /b 0


rem =======================
rem Helpers
rem =======================

:log
set "MSG=%~1"
echo [%DATE% %TIME%] %MSG%>> "%LOGFILE%"
echo %MSG%
exit /b 0

:service_exists
set "SVC=%~1"
set "SERVICE_EXISTS=0"
sc query "%SVC%" >nul 2>&1
if %errorlevel%==0 set "SERVICE_EXISTS=1"
exit /b 0

:service_is_running
set "SVC=%~1"
set "SERVICE_RUNNING=0"
for /f "tokens=3" %%a in ('sc query "%SVC%" ^| findstr /I "STATE"') do (
    if "%%a"=="4" set "SERVICE_RUNNING=1"
)
exit /b 0

:restore
rem Best-effort restore: start service if present, otherwise start instance.
call :log "Restore: attempting to start %INSTANCE% (service if present, else ampinstmgr)."
call :service_exists "%SERVICE%"
if "%SERVICE_EXISTS%"=="1" (
  call :log "Restore: starting service %SERVICE%..."
  net start "%SERVICE%" >> "%LOGFILE%" 2>&1
) else (
  call :log "Restore: starting instance %INSTANCE% via ampinstmgr..."
  ampinstmgr start "%INSTANCE%" >> "%LOGFILE%" 2>&1
)
exit /b 0
