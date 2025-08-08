@echo off
setlocal enableextensions

:: --- self-elevate to admin ---
>nul 2>&1 net session
if %errorlevel% neq 0 (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%ComSpec%' -ArgumentList '/c ""%~f0""' -Verb RunAs"
  exit /b
)

set "SCRIPT_DIR=%~dp0"
set "DL_DIR=%USERPROFILE%\Downloads"
set "TMP_SST=%TEMP%\roots.sst"
set "PS=PowerShell -NoProfile -ExecutionPolicy Bypass"

del /f /q "%cd%\RemoteSigned" 2>nul

echo.
echo ================= tdl-easy Universal Environment Fix (Win10/11) =================

for /f "tokens=2 delims=[]" %%a in ('ver') do set "OSVER=%%a"
echo OS: %OSVER%
where pwsh >nul 2>&1 && echo PowerShell 7+: detected (pwsh) || echo PowerShell 7+: not found (optional)

:: 1) ExecutionPolicy
echo [1/10] Set PowerShell ExecutionPolicy
%PS% -Command "try{Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop}catch{}"
%PS% -Command "try{Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop}catch{}"

:: 2) TLS 1.2
echo [2/10] Enable TLS 1.2 (Schannel)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" /v DisabledByDefault /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" /v Enabled /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" /v DisabledByDefault /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" /v Enabled /t REG_DWORD /d 1 /f

:: 3) TLS 1.3 (no harm if not supported)
echo [3/10] Enable TLS 1.3 (if supported)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Client" /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Client" /v DisabledByDefault /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Client" /v Enabled /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Server" /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Server" /v DisabledByDefault /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Server" /v Enabled /t REG_DWORD /d 1 /f

:: 4) .NET strong crypto + default TLS
echo [4/10] Enable .NET Strong Crypto and SystemDefaultTlsVersions
reg add "HKLM\SOFTWARE\Microsoft\.NETFramework\v4.0.30319" /v SchUseStrongCrypto /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\.NETFramework\v4.0.30319" /v SystemDefaultTlsVersions /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319" /v SchUseStrongCrypto /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319" /v SystemDefaultTlsVersions /t REG_DWORD /d 1 /f

:: 5) WinHTTP proxy sync
echo [5/10] Sync WinHTTP proxy with system settings
netsh winhttp import proxy source=ie >nul 2>&1

:: 6) Unblock-File
echo [6/10] Unblock downloaded PowerShell scripts (MOTW)
%PS% -Command "try{Get-ChildItem -Path '%SCRIPT_DIR%' -Recurse -Include *.ps1,*.psm1,*.psd1 -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue}catch{}"
%PS% -Command "try{Get-ChildItem -Path '%DL_DIR%' -Recurse -Include *.ps1,*.psm1,*.psd1 -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue}catch{}"

:: 7) Time sync
echo [7/10] Time sync (w32time)
sc query w32time | find /i "RUNNING" >nul || net start w32time >nul 2>&1
w32tm /resync >nul 2>&1

:: 8) Proxy creds for current PS session
echo [8/10] Set default proxy credentials for WebRequests (session test)
%PS% -Command "[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials"

:: 9) Connectivity tests (use -UseBasicParsing where required; treat 404 on objects as OK)
echo [9/10] Connectivity tests (TLS)
%PS% -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try{Invoke-RestMethod 'https://api.github.com' -Headers @{ 'User-Agent'='tdl-easy-fix' } -TimeoutSec 15|Out-Null; 'api.github.com: OK'}catch{'api.github.com: FAIL - ' + $_.Exception.Message}"
%PS% -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try{Invoke-WebRequest 'https://raw.githubusercontent.com/github/gitignore/main/README.md' -UseBasicParsing -TimeoutSec 15|Out-Null; 'raw.githubusercontent.com: OK'}catch{'raw.githubusercontent.com: FAIL - ' + $_.Exception.Message}"
%PS% -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try{ $req=[System.Net.HttpWebRequest]::Create('https://objects.githubusercontent.com'); $req.Method='HEAD'; $req.Timeout=15000; $null=$req.GetResponse(); 'objects.githubusercontent.com: OK' }catch{ if ($_.Exception.Response -ne $null) { 'objects.githubusercontent.com: OK (HTTP ' + [int]$_.Exception.Response.StatusCode + ')' } else { 'objects.githubusercontent.com: FAIL - ' + $_.Exception.Message } }"

:: 10) Root CA update — last, simplified, never breaks the script
echo [10/10] Update root certificates (best-effort, safe)
%PS% -Command " $ErrorActionPreference='SilentlyContinue'; $reachable=$false; try{ $r=Invoke-WebRequest -Uri 'http://ctldl.windowsupdate.com/msdownload/update/v3/static/trustedr/en/authrootstl.cab' -Method Head -TimeoutSec 10; if($r.StatusCode -ge 200 -and $r.StatusCode -lt 400){$reachable=$true} } catch {}; if($reachable){ try{ $p=Start-Process -FilePath 'certutil.exe' -ArgumentList '-generateSSTFromWU','%TMP_SST%' -PassThru -WindowStyle Hidden; if(-not (Wait-Process -Id $p.Id -Timeout 60)){ try{Stop-Process -Id $p.Id -Force}catch{} }; if(Test-Path '%TMP_SST%'){ & certutil -addstore -f root '%TMP_SST%' ^| Out-Null; & certutil -addstore -f ca '%TMP_SST%' ^| Out-Null; Remove-Item '%TMP_SST%' -Force; Write-Host 'Root CA update: OK' } else { Write-Host 'Root CA update: skipped (certutil failed)' } } catch { Write-Host 'Root CA update: skipped (error)' } } else { Write-Host 'Root CA update: skipped (WU unreachable)' } "

echo.
echo [i] Reboot is recommended to fully apply SChannel and .NET changes.
echo.
choice /C YN /M "Reboot now (recommended)?"
if errorlevel 2 (
  echo Skipping reboot. Please reboot later.
) else (
  shutdown /r /t 5 /c "Applying TLS settings and .NET strong crypto"
)

endlocal
