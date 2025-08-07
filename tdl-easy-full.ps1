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

#################################################################################################################################################
# Configuration storage in JSON file
#################################################################################################################################################
$stateFile = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath "tdl_easy.json"

function Load-Config {
    # Load configuration from JSON file, return PSCustomObject or $null
    if (Test-Path $stateFile) {
        try {
            $json = Get-Content $stateFile -Raw
            return ConvertFrom-Json $json
        } catch {
            Write-Emoji "[!] Failed to parse existing config, ignoring and starting fresh." "Yellow"
            return $null
        }
    }
    return $null
}

function Save-Config($hash) {
    # Atomically save hashtable as JSON
    $tmp = "$stateFile.tmp"
    $hash | ConvertTo-Json -Depth 5 | Set-Content -Path $tmp -Encoding UTF8
    Move-Item -Force -Path $tmp -Destination $stateFile
}

function Clear-Config {
    # Clear configuration to empty values
    $empty = @{ 
        tdl_path      = "" 
        telegramMessageUrl = "" 
        mediaDir      = "" 
        downloadLimit = "" 
        threads       = "" 
        maxRetries    = "" 
    }
    Save-Config $empty
}

# Default in-memory values
$tdl_path      = ""
$telegramMessageUrl = ""
$mediaDir      = ""
$downloadLimit = ""
$threads       = ""
$maxRetries    = 1     # Default retries set to 1
$timeoutSeconds = 300  # Increased timeout for export and download in seconds

# Load existing configuration
$existing = Load-Config
$haveAnySaved = $false
if ($existing) {
    $props = @('tdl_path','telegramMessageUrl','mediaDir','downloadLimit','threads','maxRetries')
    foreach ($p in $props) {
        if ($existing.$p -and ($existing.$p.ToString().Trim() -ne "")) {
            $haveAnySaved = $true
        }
    }
    if ($haveAnySaved) {
        $tdl_path      = $existing.tdl_path
        $telegramMessageUrl = $existing.telegramMessageUrl
        $mediaDir      = $existing.mediaDir
        $downloadLimit = $existing.downloadLimit
        $threads       = $existing.threads
        $maxRetries    = $existing.maxRetries
    }
}

$useSaved = $false
if ($haveAnySaved) {
    $resp = Read-Host "Type (Yes) to use saved parameters or type (No) to clean them and start new job"
    switch -Regex ($resp) {
        '^(?i)y(es)?$' { $useSaved = $true }
        '^(?i)n(o)?$'  {
            $useSaved = $false
            # Clear stored config both on disk and in memory
            Clear-Config
            $tdl_path = ""; $telegramMessageUrl = ""; $mediaDir = ""
            $downloadLimit = ""; $threads = ""; $maxRetries = 1
        }
        default {
            Write-Emoji "[i] Unrecognized response. Assuming use saved parameters." "Yellow"
            $useSaved = $true
        }
    }
}

# Interactive input if not using saved values
if (-not $useSaved) {
    $defaultTdl   = Split-Path -Parent $MyInvocation.MyCommand.Path
    $defaultMedia = $defaultTdl

    try {
        # TDL path
        do {
            Write-Host "";
            Write-Host "╔════════════════════ TDL PATH CONFIGURATION ════════════════════════════════╗" -ForegroundColor DarkGray
            Write-Host "║ Default: $defaultTdl" -ForegroundColor Gray
            Write-Host "╠────────────────────────────────────────────────────────────────────────────╣" -ForegroundColor DarkGray
            Write-Host "Enter the TDL path (e.g., D:\tdl, no trailing slash)"
            $input = Read-Host
            if ([string]::IsNullOrWhiteSpace($input)) {
                $tdl_path = $defaultTdl
            } else {
                $tdl_path = $input.TrimEnd('\')
            }
            if (-not (Test-Path -LiteralPath $tdl_path)) {
                Write-Emoji "[x] Error: The specified TDL path does not exist. Please try again." "Red"
                continue
            }
            break
        } while ($true)
        Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkGray

        # Media directory
        do {
            Write-Host "";
            Write-Host "╔══════════════════ MEDIA DIRECTORY CONFIGURATION ═══════════════════════════╗" -ForegroundColor DarkGray
            Write-Host "║ Default: $defaultMedia" -ForegroundColor Gray
            Write-Host "╠────────────────────────────────────────────────────────────────────────────╣" -ForegroundColor DarkGray
            Write-Host "Enter the directory for saving media files (e.g., D:\tdl\videos)"
            $input = Read-Host
            if ([string]::IsNullOrWhiteSpace($input)) {
                $mediaDir = $defaultMedia
            } else {
                $mediaDir = $input.TrimEnd('\')
            }
            if (-not (Test-Path -LiteralPath $mediaDir)) {
                Write-Emoji "[x] Error: The specified media directory does not exist. Please try again." "Red"
                continue
            }
            break
        } while ($true)
        Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkGray

        # Telegram message URL (supports topic message like https://t.me/c/2267448302/166/4857)
        do {
            Write-Host "";
            Write-Host "╔════════════════════ TELEGRAM MESSAGE URL CONFIGURATION ════════════════════╗" -ForegroundColor DarkGray
            Write-Host "║Example: https://t.me/c/123/ or https://t.me/abc/ or https://t.me/c/123/456/" -ForegroundColor Gray
            Write-Host "╠────────────────────────────────────────────────────────────────────────────╣" -ForegroundColor DarkGray
            Write-Host "Copy-Paste any message URL from the group/channel/topic"
            $input = Read-Host
            if ([string]::IsNullOrWhiteSpace($input)) {
                Write-Emoji "[x] Error: URL cannot be empty." "Red"
                continue
            }
            $input = $input.TrimEnd('/')

            if ($input -notmatch '^https?://t\.me/(?:(?:c/\d+/\d+/\d+)|(?:c/\d+/\d+)|(?:[A-Za-z0-9_]{5,32}/\d+))$') {
                Write-Emoji "[x] Error: URL must be of form https://t.me/c/12345678/123 or https://t.me/username/123 or topic message like https://t.me/c/2267448302/166/4857." "Red"
                continue
            }
            $telegramMessageUrl = $input
            break
        } while ($true)
        Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkGray

        # Concurrency settings
        do {
            Write-Host "";
            Write-Host "╔════════════════ CONCURRENCY CONFIGURATION ═════════════════════════════════╗" -ForegroundColor DarkGray
            Write-Host "║ Defaults: downloadLimit=2, threads=4, maxRetries=1" -ForegroundColor Gray
            Write-Host "╠────────────────────────────────────────────────────────────────────────────╣" -ForegroundColor DarkGray
            Write-Host "Enter max concurrent download tasks (-l, 1 to 10) [default: 2]"
            $input = Read-Host
            if ([string]::IsNullOrWhiteSpace($input)) {
                $downloadLimit = 2
                break
            }
            if ([int]::TryParse($input, [ref]$downloadLimit) -and $downloadLimit -ge 1 -and $downloadLimit -le 10) {
                break
            }
            Write-Emoji "[x] Error: Please enter a valid integer between 1 and 10 for the download limit." "Red"
        } while ($true)

        do {
            Write-Host "Enter max threads per task (-t, 1 to 8) [default: 4]"
            $input = Read-Host
            if ([string]::IsNullOrWhiteSpace($input)) {
                $threads = 4
                break
            }
            if ([int]::TryParse($input, [ref]$threads) -and $threads -ge 1 -and $threads -le 8) {
                break
            }
            Write-Emoji "[x] Error: Please enter a valid integer between 1 and 8 for the threads." "Red"
        } while ($true)

        do {
            Write-Host "Enter max retries for failed downloads (1 to 5) [default: 1]"
            $input = Read-Host
            if ([string]::IsNullOrWhiteSpace($input)) {
                $maxRetries = 1
                break
            }
            if ([int]::TryParse($input, [ref]$maxRetries) -and $maxRetries -ge 1 -and $maxRetries -le 5) {
                break
            }
            Write-Emoji "[x] Error: Please enter a valid integer between 1 and 5 for max retries." "Red"
        } while ($true)
        Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkGray

        # Persist all collected values atomically
        $toSave = @{ 
            tdl_path      = $tdl_path
            telegramMessageUrl = $telegramMessageUrl
            mediaDir      = $mediaDir
            downloadLimit = $downloadLimit
            threads       = $threads
            maxRetries    = $maxRetries
        }
        Save-Config $toSave
    } catch {
        Write-Emoji "`n[!] Input interrupted, configuration remains cleared." "Yellow"
        exit
    }
}

# Set dependent paths
$logFile = "${tdl_path}\download_log.txt"
$exportFile = "${mediaDir}\tdl-export.json"
$processedFile = "${mediaDir}\processed.txt"
$errorFile = "${mediaDir}\error_index.txt"

# Extract chat ID or username from message URL, including topic-message form, but always take only the first numeric part after c/
$channelId = $null
if ($telegramMessageUrl -match '^https?://t\.me/c/(\d+)(?:/\d+){1,2}$') {
    $channelId = $Matches[1]
} elseif ($telegramMessageUrl -match '^https?://t\.me/([A-Za-z0-9_]{5,32})/\d+$') {
    $channelId = $Matches[1]
}
if ([string]::IsNullOrWhiteSpace($channelId)) {
    Write-Emoji "[x] Error: Failed to extract chat identifier from URL: $telegramMessageUrl" "Red"
    while ($true) {
        $resp = Read-Host "Enter Telegram message URL again in form https://t.me/c/12345678/123 or https://t.me/username/123 or topic message https://t.me/c/2267448302/166/4857 or type 'quit' to exit"
        if ($resp -eq 'quit') { exit }
        if ($resp -match '^https?://t\.me/c/(\d+)(?:/\d+){1,2}$') {
            $telegramMessageUrl = $resp
            $channelId = $Matches[1]
            break
        } elseif ($resp -match '^https?://t\.me/([A-Za-z0-9_]{5,32})/\d+$') {
            $telegramMessageUrl = $resp
            $channelId = $Matches[1]
            break
        } else {
            Write-Emoji "[x] Invalid format, must be https://t.me/c/12345678/123 or https://t.me/username/123 or topic message https://t.me/c/2267448302/166/4857 exactly." "Red"
        }
    }
}

# Check for tdl.exe in the specified path
$tdlExePath = Join-Path $tdl_path "tdl.exe"
if (-not (Test-Path -LiteralPath $tdlExePath)) {
    Write-Emoji "[x] Error: tdl.exe not found in $tdl_path" "Red"
    exit
}

# Change to TDL path
Set-Location -Path $tdl_path

# PowerShell version info
$psVersion = Get-PSVersion
Write-Emoji "[i] Using PowerShell version: $psVersion" "Cyan"

# Load already processed and error indexes
$processedIds = @()
if (Test-Path $processedFile) {
    $processedIds = Get-Content $processedFile | ForEach-Object { [int]$_ }
    Write-Emoji "[f] Loaded $($processedIds.Count) processed indexes from $processedFile" "Cyan"
}

$errorIds = @()
if (Test-Path $errorFile) {
    $errorIds = Get-Content $errorFile | ForEach-Object { [int]$_ }
    Write-Emoji "[f] Loaded $($errorIds.Count) error indexes from $errorFile" "Cyan"
}

# Extract fully downloaded indexes from mediaDir
$downloadedIds = @()
if (Test-Path $mediaDir) {
    $files = Get-ChildItem -Path $mediaDir -File
    foreach ($file in $files) {
        if ($file.Name -match "^${channelId}_(\d+)_" -and $file.Length -gt 0 -and $file.Extension -ne ".tmp") {
            $downloadedIds += [int]$Matches[1]
        }
    }
    Write-Emoji "[d] Found $($downloadedIds.Count) fully downloaded indexes from files in $mediaDir" "Cyan"
}

# Combine processed, error, and downloaded for skipping
$allProcessedIds = ($processedIds + $errorIds + $downloadedIds) | Sort-Object -Unique

function Save-ProcessedId($id) {
    # Append processed ID to processed.txt
    $id | Out-File -FilePath $processedFile -Append
}

function Save-ErrorId($id) {
    # Append error ID to error_index.txt
    $id | Out-File -FilePath $errorFile -Append
}

# track if any successful download occurred
$anySuccess = $false

# Export all messages to tdl-export.json (supports numeric internal and username)
$exportCommand = ".\tdl.exe chat export -c $channelId --with-content -o `"$exportFile`""
Write-Emoji "[*] Starting export for chat ID: $channelId" "Yellow"
Write-Emoji "[c] Export Command: $exportCommand" "Gray"
"[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] Starting export for chat ID: $channelId" | Out-File -FilePath $logFile -Append
$exportCommand | Out-File -FilePath $logFile -Append

try {
    $exportOutput = Invoke-Expression $exportCommand 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor White; $_ }
    $exportOutput | Out-File -FilePath $logFile -Append

    if ($exportOutput -match "done!") {
        Write-Emoji "[+] Successfully exported messages to $exportFile" "Green"
    } else {
        Write-Emoji "[x] Failed to export messages for chat ID: $channelId" "Red"
        exit
    }
} catch {
    Write-Emoji "[x] Error executing export command: $_" "Red"
    $_ | Out-File -FilePath $logFile -Append
    exit
}

# Main download loop with retries
$retryCount = 0
while ($retryCount -lt $maxRetries) {
    Write-Emoji "[*] Starting download attempt $($retryCount + 1) of $maxRetries" "Yellow"
    $downloadCommand = ".\tdl.exe download --file `"$exportFile`" --dir `"$mediaDir`" -l $downloadLimit -t $threads --skip-same"
    Write-Emoji "[c] Download Command: $downloadCommand" "Gray"
    "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] Starting download attempt $($retryCount + 1)" | Out-File -FilePath $logFile -Append
    $downloadCommand | Out-File -FilePath $logFile -Append

    try {
        $output = Invoke-Expression $downloadCommand 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor White; $_ }
        # Timeout monitoring
        $processRunning = $true
        $startTime = Get-Date
        while ($processRunning -and ((Get-Date) - $startTime).TotalSeconds -lt $timeoutSeconds) {
            $process = Get-Process | Where-Object { $_.Path -eq "$tdl_path\tdl.exe" -and -not $_.HasExited }
            if (-not $process) { $processRunning = $false }
            Start-Sleep -Seconds 1
        }
        if ($processRunning) {
            $process | Stop-Process -Force
            Write-Emoji "[x] Timeout reached after $timeoutSeconds seconds" "Red"
            throw "Timeout"
        }
        $output | Out-File -FilePath $logFile -Append

        # Check downloaded files
        $successfulIds = @()
        $failedIds = @()
        $newFiles = Get-ChildItem -Path $mediaDir -File | Where-Object { $_.Name -match "^${channelId}_(\d+)_" -and $_.Length -gt 0 -and $_.Extension -ne ".tmp" }
        foreach ($file in $newFiles) {
            if ($file.Name -match "^${channelId}_(\d+)_") {
                $id = [int]$Matches[1]
                if (-not ($allProcessedIds -contains $id)) {
                    $successfulIds += $id
                    Write-Emoji "[ok] Downloaded $($file.Name) for index $id" "Green"
                    Save-ProcessedId $id
                }
            }
        }

        # Check for errors in output
        if ($output -match "Error:.*the message \d+/(\d+)") {
            foreach ($match in ($output | Select-String "Error:.*the message \d+/(\d+)")) {
                $failedId = [int]$match.Matches.Groups[1].Value
                if (-not ($allProcessedIds -contains $failedId)) {
                    $failedIds += $failedId
                    Write-Emoji "[x] Failed to download index $failedId (may be deleted or empty)" "Red"
                    Save-ErrorId $failedId
                }
            }
        }

        # Summarize the batch result
        if ($successfulIds.Count -gt 0 -and $failedIds.Count -eq 0) {
            Write-Emoji "[+] Successfully downloaded indexes: $($successfulIds -join ',')" "Green"
            $anySuccess = $true
            break
        } elseif ($successfulIds.Count -gt 0 -and $failedIds.Count -gt 0) {
            Write-Emoji "[*] Partial success: $($successfulIds -join ',') downloaded; $($failedIds -join ',') failed" "Yellow"
            $anySuccess = $true
            break
        } elseif ($failedIds.Count -gt 0) {
            Write-Emoji "[x] Failed indexes: $($failedIds -join ',')" "Red"
            $retryCount++
            if ($retryCount -ge $maxRetries) {
                Write-Emoji "[x] Exceeded max retries ($maxRetries)" "Red"
                break
            }
            Write-Emoji "[*] Retrying download..." "Yellow"
            continue
        } else {
            Write-Emoji "[x] No new files downloaded or errors reported" "Red"
            $retryCount++
            if ($retryCount -ge $maxRetries) {
                Write-Emoji "[x] Exceeded max retries ($maxRetries)" "Red"
                break
            }
            Write-Emoji "[*] Retrying download..." "Yellow"
            continue
        }
    } catch {
        Write-Emoji "[x] Error executing download command: $_" "Red"
        $_ | Out-File -FilePath $logFile -Append
        $retryCount++
        if ($retryCount -ge $maxRetries) {
            Write-Emoji "[x] Exceeded max retries ($maxRetries)" "Red"
            break
        }
        Write-Emoji "[*] Retrying download..." "Yellow"
    }
}

# Clean up incomplete files
$incompleteFiles = Get-ChildItem -Path $mediaDir -File | Where-Object { $_.Name -match "^${channelId}_\d+_.*" -and $_.Length -eq 0 }
foreach ($incompleteFile in $incompleteFiles) {
    Remove-Item -Path $incompleteFile.FullName -Force
    Write-Emoji "[x] Removed incomplete file $($incompleteFile.Name)" "Red"
}

# Cleanup export, processed, and error files after completion
if (Test-Path $exportFile) {
    Remove-Item -Path $exportFile -Force
    Write-Emoji "[del] File $exportFile deleted after completion." "Cyan"
}
if (Test-Path $processedFile) {
    Remove-Item -Path $processedFile -Force
    Write-Emoji "[del] File $processedFile deleted after completion." "Cyan"
}
if (Test-Path $errorFile) {
    Remove-Item -Path $errorFile -Force
    Write-Emoji "[del] File $errorFile deleted after completion." "Cyan"
}

# Auto-open folder if any successful download happened
if ($anySuccess) {
    Write-Emoji "[d] Opening download folder: $mediaDir" "Cyan"
    try {
        Start-Process explorer.exe -ArgumentList $mediaDir
    } catch {
        Write-Emoji "[!] Не удалось открыть папку: $_" "Yellow"
    }
}

Write-Emoji "[done] Completed! All indexes processed." "Cyan"
