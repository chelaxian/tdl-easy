# Interrupt handling: clean exit on Ctrl+C
trap [System.OperationCanceledException] {
    Write-Host "`n⚠️ Interrupted by user." -ForegroundColor Yellow
    exit
}

#################################################################################################################################################
# Configuration storage in JSON file
#################################################################################################################################################
$stateFile = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath "tdl_easy_runner.json"

function Load-Config {
    # Load configuration from JSON file, return PSCustomObject or $null
    if (Test-Path $stateFile) {
        try {
            $json = Get-Content $stateFile -Raw
            return ConvertFrom-Json $json
        } catch {
            Write-Host "⚠️ Failed to parse existing config, ignoring and starting fresh." -ForegroundColor Yellow
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
        telegramUrl   = "" 
        mediaDir      = "" 
        startId       = "" 
        endId         = "" 
        downloadLimit = "" 
        threads       = "" 
    }
    Save-Config $empty
}

# Default in-memory values
$tdl_path      = ""
$telegramUrl   = ""
$mediaDir      = ""
$startId       = ""
$endId         = ""
$downloadLimit = ""
$threads       = ""
$timeoutSeconds = 120  # timeout for each download in seconds
$maxRetries     = 3    # max retries for failed downloads

# Load existing configuration
$existing = Load-Config
$haveAnySaved = $false
if ($existing) {
    $props = @('tdl_path','telegramUrl','mediaDir','startId','endId','downloadLimit','threads')
    foreach ($p in $props) {
        if ($existing.$p -and ($existing.$p.ToString().Trim() -ne "")) {
            $haveAnySaved = $true
        }
    }
    if ($haveAnySaved) {
        $tdl_path      = $existing.tdl_path
        $telegramUrl   = $existing.telegramUrl
        $mediaDir      = $existing.mediaDir
        $startId       = $existing.startId
        $endId         = $existing.endId
        $downloadLimit = $existing.downloadLimit
        $threads       = $existing.threads
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
            $tdl_path = ""; $telegramUrl = ""; $mediaDir = ""
            $startId   = ""; $endId       = ""; $downloadLimit = ""; $threads = ""
        }
        default {
            Write-Host "ℹ️ Unrecognized response. Assuming use saved parameters." -ForegroundColor Yellow
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
                Write-Host "🔴 Error: The specified TDL path does not exist. Please try again." -ForegroundColor Red
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
                Write-Host "🔴 Error: The specified media directory does not exist. Please try again." -ForegroundColor Red
                continue
            }
            break
        } while ($true)
        Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkGray

        # Telegram URL (only /c/<digits>/ format)
        do {
            Write-Host "";
            Write-Host "╔════════════════════ TELEGRAM URL CONFIGURATION ════════════════════════════╗" -ForegroundColor DarkGray
            Write-Host "║ Example: https://t.me/c/12345678/ (only this format is accepted)" -ForegroundColor Gray
            Write-Host "╠────────────────────────────────────────────────────────────────────────────╣" -ForegroundColor DarkGray
            Write-Host "Copy-Paste group/channel any message base URL without message index in the end" 
            $input = Read-Host
            if ([string]::IsNullOrWhiteSpace($input)) {
                Write-Host "🔴 Error: URL cannot be empty." -ForegroundColor Red
                continue
            }
            if (-not $input.EndsWith("/")) { $input = "$input/" }
            if ($input -notmatch '^https?://t\.me/c/\d+/$') {
                Write-Host "🔴 Error: URL must be of form https://t.me/c/12345678/ exactly." -ForegroundColor Red
                continue
            }
            $telegramUrl = $input
            break
        } while ($true)
        Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkGray

        # Index range configuration
        do {
            Write-Host "";
            Write-Host "╔══════════════════ INDEX RANGE CONFIGURATION ═══════════════════════════════╗" -ForegroundColor DarkGray
            Write-Host "║ Defaults: startId=1, endId=100 (endId forced >= startId)" -ForegroundColor Gray
            Write-Host "╠────────────────────────────────────────────────────────────────────────────╣" -ForegroundColor DarkGray
            Write-Host "Enter the starting message index (positive integer) [default: 1]"
            $input = Read-Host
            if ([string]::IsNullOrWhiteSpace($input)) {
                $startId = 1
                break
            }
            if ([int]::TryParse($input, [ref]$startId) -and $startId -gt 0) {
                break
            }
            Write-Host "🔴 Error: Please enter a valid positive integer for the starting index." -ForegroundColor Red
        } while ($true)

        do {
            $defaultEnd = 100
            if (($startId -is [int]) -and $startId -gt $defaultEnd) { $defaultEnd = $startId }
            Write-Host "Enter the ending message index (must be >= $startId) [default: $defaultEnd]"
            $input = Read-Host
            if ([string]::IsNullOrWhiteSpace($input)) {
                $endId = $defaultEnd
            } elseif ([int]::TryParse($input, [ref]$endId) -and $endId -ge $startId) {
                # ok
            } else {
                Write-Host "🔴 Error: Please enter a valid integer >= $startId for the ending index." -ForegroundColor Red
                continue
            }
            if ($endId -lt $startId) {
                Write-Host "🔴 Error: ending index must be >= starting index." -ForegroundColor Red
                continue
            }
            break
        } while ($true)
        Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkGray

        # Concurrency settings
        do {
            Write-Host "";
            Write-Host "╔════════════════ CONCURRENCY CONFIGURATION ═════════════════════════════════╗" -ForegroundColor DarkGray
            Write-Host "║ Defaults: downloadLimit=2, threads=4" -ForegroundColor Gray
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
            Write-Host "🔴 Error: Please enter a valid integer between 1 and 10 for the download limit." -ForegroundColor Red
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
            Write-Host "🔴 Error: Please enter a valid integer between 1 and 8 for the threads." -ForegroundColor Red
        } while ($true)
        Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkGray

        # Persist all collected values atomically
        $toSave = @{ 
            tdl_path      = $tdl_path
            telegramUrl   = $telegramUrl
            mediaDir      = $mediaDir
            startId       = $startId
            endId         = $endId
            downloadLimit = $downloadLimit
            threads       = $threads
        }
        Save-Config $toSave
    } catch {
        Write-Host "`n⚠️ Input interrupted, configuration remains cleared." -ForegroundColor Yellow
        exit
    }
}

# ====================================================================================================
# Main script logic continues below
# ====================================================================================================

# Set dependent paths
$logFile = "${tdl_path}\download_log.txt"
$processedFile = "${tdl_path}\processed.txt"

# Extract channel ID from URL
$channelId = $null
if ($telegramUrl -match '^https?://t\.me/c/(\d+)/$') {
    $channelId = $Matches[1]
}
if ([string]::IsNullOrWhiteSpace($channelId)) {
    Write-Host "🔴 Error: Failed to extract channel ID from URL: $telegramUrl" -ForegroundColor Red
    # fallback: ask again
    while ($true) {
        $resp = Read-Host "Enter Telegram URL again in form https://t.me/c/12345678/ or type 'quit' to exit"
        if ($resp -eq 'quit') { exit }
        if (-not $resp.EndsWith("/")) { $resp = "$resp/" }
        if ($resp -match '^https?://t\.me/c/(\d+)/$') {
            $telegramUrl = $resp
            $channelId = $Matches[1]
            break
        } else {
            Write-Host "🔴 Invalid format, must be https://t.me/c/12345678/ exactly." -ForegroundColor Red
        }
    }
}

# Change to TDL path
Set-Location -Path $tdl_path

# Check for tdl.exe
if (-not (Test-Path ".\tdl.exe")) {
    Write-Host "🔴 Error: tdl.exe not found in $tdl_path" -ForegroundColor Red
    exit
}

# PowerShell version info
$psVersion = $PSVersionTable.PSVersion
Write-Host "ℹ️ Using PowerShell version: $psVersion" -ForegroundColor Cyan

# Load already processed indexes
$processedIds = @()
if (Test-Path $processedFile) {
    $processedIds = Get-Content $processedFile | ForEach-Object { [int]$_ }
    Write-Host "📜 Loaded $($processedIds.Count) processed indexes from $processedFile" -ForegroundColor Cyan
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
    Write-Host "📂 Found $($downloadedIds.Count) fully downloaded indexes from files in $mediaDir" -ForegroundColor Cyan
}

# Combine processed and downloaded for skipping
$allProcessedIds = ($processedIds + $downloadedIds) | Sort-Object -Unique

function Save-ProcessedId($id) {
    # Append processed ID to processed.txt
    $id | Out-File -FilePath $processedFile -Append
}

# Main download loop
$currentId = $startId
$retryCount = 0
while ($currentId -le $endId) {
    # Skip already processed or downloaded
    while ($currentId -le $endId -and $allProcessedIds -contains $currentId) {
        Write-Host "⏭️ Skipped index: $currentId (processed or fully downloaded)" -ForegroundColor Cyan
        $currentId++
    }
    if ($currentId -gt $endId) { break }

    # Form batch
    $batch = @($currentId)
    $nextId = $currentId + 1
    $batchSize = [math]::Min($downloadLimit, $endId - $currentId + 1)
    for ($i = 1; $i -lt $batchSize; $i++) {
        if ($nextId -le $endId -and -not ($allProcessedIds -contains $nextId)) {
            $batch += $nextId
        } else { break }
        $nextId++
    }

    Write-Host "📋 Debug: Batch contains $($batch.Count) URLs" -ForegroundColor Gray

    # Build and run command
    $urls = $batch | ForEach-Object { "`"$telegramUrl$_`"" }
    $command = ".\tdl.exe download --desc --dir `"$mediaDir`" --url $($urls -join ' --url ') -l $downloadLimit -t $threads"
    $pair = $batch -join ","

    Write-Host "🟡 Starting download for indexes: $pair" -ForegroundColor Yellow
    Write-Host "📋 Command: $command" -ForegroundColor Gray
    "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] Starting: $pair" | Out-File -FilePath $logFile -Append
    $command | Out-File -FilePath $logFile -Append

    try {
        $output = Invoke-Expression $command 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor White; $_ }
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
            Write-Host "🔴 Timeout reached for: $pair after $timeoutSeconds seconds" -ForegroundColor Red
            throw "Timeout"
        }
        $output | Out-File -FilePath $logFile -Append

        if ($output -match "done!") {
            Write-Host "🟢 Successfully downloaded: $pair" -ForegroundColor Green
            foreach ($id in $batch) {
                $downloadedFile = Get-ChildItem -Path $mediaDir -File | Where-Object { $_.Name -match "^${channelId}_${id}_.*" -and $_.Length -gt 0 }
                if ($downloadedFile) { Write-Host "✅ Downloaded $($downloadedFile.Name)" -ForegroundColor Green }
                Save-ProcessedId $id
            }
            $retryCount = 0
        } else {
            Write-Host "🔴 Error downloading: $pair" -ForegroundColor Red
            foreach ($id in $batch) {
                $incompleteFile = Get-ChildItem -Path $mediaDir -File | Where-Object { $_.Name -match "^${channelId}_${id}_.*" -and $_.Length -eq 0 }
                if ($incompleteFile) { Remove-Item -Path $incompleteFile.FullName -Force; Write-Host "❌ Removed incomplete file $($incompleteFile.Name)" -ForegroundColor Red }
            }
            $retryCount++
            if ($retryCount -ge $maxRetries) { Write-Host "🔴 Exceeded max retries ($maxRetries) for: $pair" -ForegroundColor Red; $currentId = $batch[-1] + 1 }
        }
    } catch {
        Write-Host "🔴 Error executing command for: $pair - $_" -ForegroundColor Red
        foreach ($id in $batch) {
            $incompleteFile = Get-ChildItem -Path $mediaDir -File | Where-Object { $_.Name -match "^${channelId}_${id}_.*" -and $_.Length -eq 0 }
            if ($incompleteFile) { Remove-Item -Path $incompleteFile.FullName -Force; Write-Host "❌ Removed incomplete file $($incompleteFile.Name)" -ForegroundColor Red }
        }
        $_ | Out-File -FilePath $logFile -Append
        $retryCount++
        if ($retryCount -ge $maxRetries) { Write-Host "🔴 Exceeded max retries ($maxRetries) for: $pair" -ForegroundColor Red; $currentId = $batch[-1] + 1 }
    }

    if ($output -match "done!" -or $retryCount -ge $maxRetries) {
        $currentId = $batch[-1] + 1
    } else {
        Write-Host "🔶 Retrying batch: $pair" -ForegroundColor Yellow
    }
}

# Cleanup processed file after all
if ($currentId -gt $endId -and (Test-Path $processedFile)) {
    Remove-Item -Path $processedFile -Force
    Write-Host "🗑️ File $processedFile deleted after completion." -ForegroundColor Cyan
}

Write-Host "🎉 Completed! All indexes processed." -ForegroundColor Cyan
