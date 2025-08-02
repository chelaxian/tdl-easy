# Interrupt handling: clean exit on Ctrl+C
trap [System.OperationCanceledException] {
    Write-Host "`n⚠️ Interrupted by user." -ForegroundColor Yellow
    exit
}

# Set paths
$tdl_path = Split-Path -Parent $MyInvocation.MyCommand.Path
$mediaDir = $tdl_path
$logFile = Join-Path -Path $tdl_path -ChildPath "download_log.txt"

# Change to TDL path
Set-Location -Path $tdl_path

# Check for tdl.exe
if (-not (Test-Path ".\tdl.exe")) {
    Write-Host "🔴 Error: tdl.exe not found in $tdl_path" -ForegroundColor Red
    exit
}

# Interactive input for Telegram URL (including topic links like https://t.me/c/2267448302/166/4857)
do {
    Write-Host "";
    Write-Host "╔════════════════════ TELEGRAM URL CONFIGURATION ════════════════════════════╗" -ForegroundColor DarkGray
    Write-Host "║ Examples: https://t.me/c/12345678/123 or https://t.me/abc/123 or https://t.me/c/2267448302/166/4857" -ForegroundColor Gray
    Write-Host "╠────────────────────────────────────────────────────────────────────────────╣" -ForegroundColor DarkGray
    Write-Host "Copy link to Telegram post (with or without topic) and paste it here"
    $telegramUrl = Read-Host

    if ([string]::IsNullOrWhiteSpace($telegramUrl)) {
        Write-Host "🔴 Error: URL cannot be empty." -ForegroundColor Red
        continue
    }

    # normalize: strip trailing slash
    $telegramUrl = $telegramUrl.TrimEnd('/')

    # Accept:
    # - public username message: https://t.me/username/123
    # - internal channel message: https://t.me/c/12345678/123
    # - forum topic message: https://t.me/c/12345678/<topic_id>/<message_id>
    if ($telegramUrl -notmatch '^https?://t\.me/(?:c/\d+/\d+(?:/\d+)?|[A-Za-z0-9_]+/\d+)$') {
        Write-Host "🔴 Error: URL must be one of forms: https://t.me/c/12345678/123 , https://t.me/abc/123 or topic link like https://t.me/c/2267448302/166/4857" -ForegroundColor Red
        continue
    }

    break
} while ($true)
Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkGray

# Build and run command
$command = ".\tdl.exe download --desc --dir `"$mediaDir`" --url `"$telegramUrl`""
Write-Host "🟡 Starting download for URL: $telegramUrl" -ForegroundColor Yellow
Write-Host "📋 Command: $command" -ForegroundColor Gray
"[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] Starting: $telegramUrl" | Out-File -FilePath $logFile -Append
$command | Out-File -FilePath $logFile -Append

try {
    $output = Invoke-Expression $command 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor White; $_ }
    $output | Out-File -FilePath $logFile -Append
    Write-Host "🟢 Successfully downloaded: $telegramUrl" -ForegroundColor Green
} catch {
    Write-Host "🔴 Error downloading: $telegramUrl - $_" -ForegroundColor Red
    $_ | Out-File -FilePath $logFile -Append
}

# Open the download folder in Windows Explorer
Write-Host "📂 Opening download folder: $mediaDir" -ForegroundColor Cyan
Start-Process explorer.exe -ArgumentList $mediaDir

Write-Host "🎉 Completed!" -ForegroundColor Cyan
