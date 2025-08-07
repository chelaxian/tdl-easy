# Interrupt handling: clean exit on Ctrl+C
trap [System.OperationCanceledException] {
    Write-Host "`n[!] Interrupted by user." -ForegroundColor Yellow
    exit
}

# PowerShell version detection and emoji compatibility
function Get-PSVersion {
    try {
        return $PSVersionTable.PSVersion.Major
    } catch {
        return 5  # Default to 5 if detection fails
    }
}

function Write-Emoji {
    param(
        [string]$Text,
        [string]$Color = "White"
    )
    $psVersion = Get-PSVersion
    if ($psVersion -ge 7) {
        Write-Host $Text -ForegroundColor $Color
    } else {
        # Replace emojis with ASCII equivalents for PS 5.x
        $asciiText = $Text -replace "⚠️", "[!]" -replace "ℹ️", "[i]" -replace "🟡", "[*]" -replace "🟢", "[+]" -replace "🔴", "[x]" -replace "📜", "[f]" -replace "📂", "[d]" -replace "⏭️", "[s]" -replace "📋", "[c]" -replace "✅", "[ok]" -replace "🗑️", "[del]" -replace "🎉", "[done]"
        Write-Host $asciiText -ForegroundColor $Color
    }
}

# Set paths
$tdl_path = Split-Path -Parent $MyInvocation.MyCommand.Path
$mediaDir = $tdl_path
$logFile = Join-Path -Path $tdl_path -ChildPath "download_log.txt"

# Change to TDL path
Set-Location -Path $tdl_path

# Check for tdl.exe in the specified path
$tdlExePath = Join-Path $tdl_path "tdl.exe"
if (-not (Test-Path -LiteralPath $tdlExePath)) {
    Write-Emoji "[x] Error: tdl.exe not found in $tdl_path" "Red"
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
        Write-Emoji "[x] Error: URL cannot be empty." "Red"
        continue
    }

    # normalize: strip trailing slash
    $telegramUrl = $telegramUrl.TrimEnd('/')

    # Accept:
    # - public username message: https://t.me/username/123
    # - internal channel message: https://t.me/c/12345678/123
    # - forum topic message: https://t.me/c/12345678/<topic_id>/<message_id>
    if ($telegramUrl -notmatch '^https?://t\.me/(?:c/\d+/\d+(?:/\d+)?|[A-Za-z0-9_]+/\d+)$') {
        Write-Emoji "[x] Error: URL must be one of forms: https://t.me/c/12345678/123 , https://t.me/abc/123 or topic link like https://t.me/c/2267448302/166/4857" "Red"
        continue
    }

    break
} while ($true)
Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkGray

# Build and run command
$command = ".\tdl.exe download --desc --dir `"$mediaDir`" --url `"$telegramUrl`""
Write-Emoji "[*] Starting download for URL: $telegramUrl" "Yellow"
Write-Emoji "[c] Command: $command" "Gray"
"[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] Starting: $telegramUrl" | Out-File -FilePath $logFile -Append
$command | Out-File -FilePath $logFile -Append

try {
    $output = Invoke-Expression $command 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor White; $_ }
    $output | Out-File -FilePath $logFile -Append
    Write-Emoji "[+] Successfully downloaded: $telegramUrl" "Green"
} catch {
    Write-Emoji "[x] Error downloading: $telegramUrl - $_" "Red"
    $_ | Out-File -FilePath $logFile -Append
}

# Open the download folder in Windows Explorer
Write-Emoji "[d] Opening download folder: $mediaDir" "Cyan"
Start-Process explorer.exe -ArgumentList $mediaDir

Write-Emoji "[done] Completed!" "Cyan"
