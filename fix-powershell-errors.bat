@echo off
setlocal enableextensions

:: ------------------------------
:: Self-elevate to Administrator
:: ------------------------------
>nul 2>&1 net session
if %errorlevel% NEQ 0 (
  echo [*] Elevation required. Restarting as Administrator...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo.
echo ================= TLS / PowerShell Fix =================

:: 1) Set PowerShell execution policy for CurrentUser to RemoteSigned
echo [1/5] Setting PowerShell ExecutionPolicy for CurrentUser => RemoteSigned
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force"

:: 2) Enable TLS 1.2 in SChannel (Client + Server)
echo [2/5] Enabling TLS 1.2 in SChannel (Client/Server)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" /v DisabledByDefault /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" /v Enabled           /t REG_DWORD /d 1 /f

reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" /v DisabledByDefault /t REG_DWORD /d 0 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" /v Enabled           /t REG_DWORD /d 1 /f

:: 3) Enable .NET strong crypto + default TLS selection (x64 + x86)
echo [3/5] Enabling .NET Strong Crypto (x64/x86)
reg add "HKLM\SOFTWARE\Microsoft\.NETFramework\v4.0.30319" /v SchUseStrongCrypto      /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\.NETFramework\v4.0.30319" /v SystemDefaultTlsVersions /t REG_DWORD /d 1 /f

reg add "HKLM\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319" /v SchUseStrongCrypto      /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319" /v SystemDefaultTlsVersions /t REG_DWORD /d 1 /f

:: 4) Optional: let WebRequests use default proxy creds (helps behind corporate proxy)
echo [4/5] Setting default proxy credentials for WebRequests (session only test)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials"

:: 5) Quick TLS 1.2 connectivity test to GitHub API
echo [5/5] TLS 1.2 connectivity test to GitHub...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue';" ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
  "try{ Invoke-RestMethod -Uri 'https://api.github.com' -Headers @{ 'User-Agent'='tdl-updater-test' } -TimeoutSec 15 | Out-Null; Write-Host 'TLS 1.2 test: OK' } catch { Write-Host 'TLS 1.2 test: FAILED'; Write-Host $_.Exception.Message }"

echo.
echo [i] Changes to SChannel/.NET typically require a reboot to fully apply.
echo.

choice /M "Reboot now (recommended)?" /C YN
if errorlevel 2 (
  echo Skipping reboot. Please reboot later.
) else (
  shutdown /r /t 5 /c "Applying TLS 1.2 and .NET strong crypto settings"
)

endlocal
