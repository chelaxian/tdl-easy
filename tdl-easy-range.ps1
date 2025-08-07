# Interrupt handling: clean exit on Ctrl+C
trap [System.OperationCanceledException] {
    Write-Host "`n[!] Interrupted by user." -ForegroundColor Yellow
    exit
}

# Simple colored output function
function Write-Emoji {
    param(
        [string]$Text,
        [string]$Color = "White"
    )
    Write-Host $Text -ForegroundColor $Color
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
        telegramUrl   = "" 
        mediaDir      = "" 
        startId       = "" 
        endId         = "" 
        downloadLimit = "" 
        threads       = "" 
        maxRetries    = "" 
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
$maxRetries    = 1     # Default retries set to 1
$timeoutSeconds = 120  # timeout for each download in seconds

# Load existing configuration
$existing = Load-Config
$haveAnySaved = $false
if ($existing) {
    $props = @('tdl_path','telegramUrl','mediaDir','startId','endId','downloadLimit','threads','maxRetries')
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
            $tdl_path = ""; $telegramUrl = ""; $mediaDir = ""
            $startId   = ""; $endId       = ""; $downloadLimit = ""; $threads = ""; $maxRetries = 1
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
            Write-Host "+================================ TDL PATH CONFIGURATION ================================+" -ForegroundColor DarkGray
            Write-Host "| Default: $defaultTdl" -ForegroundColor Gray
            Write-Host "+----------------------------------------------------------------------------------------+" -ForegroundColor DarkGray
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
        Write-Host "+===============================================================================+" -ForegroundColor DarkGray

        # Media directory
        do {
            Write-Host "";
            Write-Host "+============================= MEDIA DIRECTORY CONFIGURATION =============================" -ForegroundColor DarkGray
            Write-Host "| Default: $defaultMedia" -ForegroundColor Gray
            Write-Host "+----------------------------------------------------------------------------------------+" -ForegroundColor DarkGray
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
        Write-Host "+===============================================================================+" -ForegroundColor DarkGray

        # Telegram base URL input (supports username base, internal base, or topic base)
        do {
            Write-Host "";
            Write-Host "+============================= TELEGRAM URL CONFIGURATION ================================" -ForegroundColor DarkGray
            Write-Host "|Example: https://t.me/c/123/ or https://t.me/abc/ or https://t.me/c/123/456/" -ForegroundColor Gray
            Write-Host "+----------------------------------------------------------------------------------------+" -ForegroundColor DarkGray
            Write-Host "Copy-Paste Telegram channel/group/topic base URL (no message index in the end)"
            $input = Read-Host
            if ([string]::IsNullOrWhiteSpace($input)) {
                Write-Emoji "[x] Error: URL cannot be empty." "Red"
                continue
            }
            if (-not $input.EndsWith("/")) { $input = "$input/" }

            try {
                $parsedUri = [uri]$input
            } catch {
                Write-Emoji "[x] Error: Invalid URL format." "Red"
                continue
            }

            if ($parsedUri.Scheme -notin @('http', 'https') -or $parsedUri.Host -ne 't.me') {
                Write-Emoji "[x] Error: URL must be https://t.me/..." "Red"
                continue
            }

            $segments = $parsedUri.AbsolutePath.Trim('/').Split('/')
            $isValidBase = $false

            if ($segments.Length -eq 1 -and $segments[0] -match '^[A-Za-z0-9_]{5,32}$') {
                # public username
                $isValidBase = $true
            } elseif ($segments.Length -eq 2 -and $segments[0] -eq 'c' -and $segments[1] -match '^\d+$') {
                # internal channel base
                $isValidBase = $true
            } elseif ($segments.Length -eq 3 -and $segments[0] -eq 'c' -and $segments[1] -match '^\d+$' -and $segments[2] -match '^\d+$') {
                # topic base
                $isValidBase = $true
            }

            if (-not $isValidBase) {
                Write-Emoji "[x] Error: URL должен быть https://t.me/c/12345678/ или https://t.me/username/ или topic base https://t.me/c/2267448302/166/." "Red"
                continue
            }

            $telegramUrl = $input
            break
        } while ($true)
        Write-Host "+===============================================================================+" -ForegroundColor DarkGray

        # Index range configuration
        do {
            Write-Host "";
            Write-Host "+============================= INDEX RANGE CONFIGURATION =================================" -ForegroundColor DarkGray
            Write-Host "| Defaults: startId=1, endId=100 (endId forced >= startId)" -ForegroundColor Gray
            Write-Host "+----------------------------------------------------------------------------------------+" -ForegroundColor DarkGray
            Write-Host "Enter the starting message index (positive integer) [default: 1]"
            $input = Read-Host
            if ([string]::IsNullOrWhiteSpace($input)) {
                $startId = 1
                break
            }
            if ([int]::TryParse($input, [ref]$startId) -and $startId -gt 0) {
                break
            }
            Write-Emoji "[x] Error: Please enter a valid positive integer for the starting index." "Red"
        } while ($true)

        do {
            Write-Host "Enter the ending message index (must be >= $startId) [default: $($startId+99)]"
            $input = Read-Host
            if ([string]::IsNullOrWhiteSpace($input)) {
                $endId = $startId + 99
                break
            }
            if ([int]::TryParse($input, [ref]$endId) -and $endId -ge $startId) {
                break
            }
            Write-Emoji "[x] Error: Please enter a valid integer >= $startId for the ending index." "Red"
        } while ($true)

        if ($endId -lt $startId) {
            Write-Emoji "[x] Error: ending index must be >= starting index." "Red"
            exit
        }

        # Concurrency settings
        do {
            Write-Host "";
            Write-Host "+=============================== CONCURRENCY CONFIGURATION ===============================" -ForegroundColor DarkGray
            Write-Host "| Defaults: downloadLimit=2, threads=4" -ForegroundColor Gray
            Write-Host "+----------------------------------------------------------------------------------------+" -ForegroundColor DarkGray
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
        Write-Host "+===============================================================================+" -ForegroundColor DarkGray

        # Persist all collected values atomically
        $toSave = @{ 
            tdl_path      = $tdl_path
            telegramUrl   = $telegramUrl
            mediaDir      = $mediaDir
            startId       = $startId
            endId         = $endId
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
$processedFile = "${mediaDir}\processed.txt"
$errorFile = "${mediaDir}\error_index.txt"

# Extract channel/group identifier from base URL
$channelId = $null
if ($telegramUrl -match '^https?://t\.me/c/(\d+)(?:/\d+)?/$') {
    $channelId = $Matches[1]
} elseif ($telegramUrl -match '^https?://t\.me/([A-Za-z0-9_]{5,32})/$') {
    $channelId = $Matches[1]
}
if ([string]::IsNullOrWhiteSpace($channelId)) {
    Write-Emoji "[x] Error: Failed to extract channel/group identifier from URL: $telegramUrl" "Red"
    while ($true) {
        $resp = Read-Host "Enter Telegram base URL again in form https://t.me/c/12345678/ or https://t.me/username/ or topic base https://t.me/c/2267448302/166/ or type 'quit' to exit"
        if ($resp -eq 'quit') { exit }
        if ($resp -match '^https?://t\.me/c/(\d+)(?:/\d+)?/$') {
            $telegramUrl = $resp
            $channelId = $Matches[1]
            break
        } elseif ($resp -match '^https?://t\.me/([A-Za-z0-9_]{5,32})/$') {
            $telegramUrl = $resp
            $channelId = $Matches[1]
            break
        } else {
            Write-Emoji "[x] Invalid format, should be https://t.me/c/12345678/ or https://t.me/c/2267448302/166/ or https://t.me/username/." "Red"
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
Write-Emoji "[i] Starting download process..." "Cyan"

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

# Main download loop with retries
$retryCount = 0
while ($retryCount -lt $maxRetries) {
    Write-Emoji "[*] Starting download attempt $($retryCount + 1) of $maxRetries" "Yellow"
    
    # Collect all unprocessed indexes
    $unprocessedIds = @()
    for ($i = $startId; $i -le $endId; $i++) {
        if (-not ($allProcessedIds -contains $i)) {
            $unprocessedIds += $i
        }
    }
    
    if ($unprocessedIds.Count -eq 0) {
        Write-Emoji "[+] All indexes processed successfully!" "Green"
        break
    }
    
    Write-Emoji "[i] Processing $($unprocessedIds.Count) unprocessed indexes in batches of $downloadLimit" "Cyan"
    
    # Process indexes in batches of downloadLimit
    for ($batchStart = 0; $batchStart -lt $unprocessedIds.Count; $batchStart += $downloadLimit) {
        $batchEnd = [Math]::Min($batchStart + $downloadLimit - 1, $unprocessedIds.Count - 1)
        $batchIds = $unprocessedIds[$batchStart..$batchEnd]
        
        Write-Emoji "[c] Processing batch: $($batchIds -join ', ')" "Gray"
        
        # Build URLs for current batch
        $urls = @()
        foreach ($id in $batchIds) {
            $urls += $telegramUrl + $id.ToString()
        }
        
        # Build command with multiple URLs
        $urlArgs = $urls | ForEach-Object { "--url `"$_`"" }
        $command = ".\tdl.exe download --desc --dir `"$mediaDir`" $($urlArgs -join ' ') -l $downloadLimit -t $threads"
        
        Write-Emoji "[c] Command: $command" "Gray"
        "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] Processing batch: $($batchIds -join ', ')" | Out-File -FilePath $logFile -Append
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
                Write-Emoji "[x] Timeout reached for batch after $timeoutSeconds seconds" "Red"
                throw "Timeout"
            }
            
            $output | Out-File -FilePath $logFile -Append

            # Check for downloaded files for each ID in batch
            $successCount = 0
            foreach ($id in $batchIds) {
                $downloadedFile = Get-ChildItem -Path $mediaDir -File | Where-Object { $_.Name -match "^${channelId}_${id}_" -and $_.Length -gt 0 -and $_.Extension -ne ".tmp" } | Select-Object -First 1
                if ($downloadedFile) {
                    Write-Emoji "[ok] Downloaded $($downloadedFile.Name) for index $id" "Green"
                    Save-ProcessedId $id
                    $allProcessedIds += $id
                    $successCount++
                } else {
                    Write-Emoji "[x] Failed to download index $id (may be deleted or empty)" "Red"
                    Save-ErrorId $id
                    $allProcessedIds += $id
                }
            }
            
            Write-Emoji "[+] Batch completed: $successCount/$($batchIds.Count) successful" "Green"
            
        } catch {
            Write-Emoji "[x] Error executing command for batch: $_" "Red"
            $_ | Out-File -FilePath $logFile -Append
            # Mark all IDs in batch as errors
            foreach ($id in $batchIds) {
                Save-ErrorId $id
                $allProcessedIds += $id
            }
        }
    }

    # Check if we need to retry
    $remainingIds = @()
    for ($i = $startId; $i -le $endId; $i++) {
        if (-not ($allProcessedIds -contains $i)) {
            $remainingIds += $i
        }
    }

    if ($remainingIds.Count -eq 0) {
        Write-Emoji "[+] All indexes processed successfully!" "Green"
        break
    } else {
        Write-Emoji "[*] Remaining indexes: $($remainingIds -join ',')" "Yellow"
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

# Cleanup processed and error files after completion
if (Test-Path $processedFile) {
    Remove-Item -Path $processedFile -Force
    Write-Emoji "[del] File $processedFile deleted after completion." "Cyan"
}
if (Test-Path $errorFile) {
    Remove-Item -Path $errorFile -Force
    Write-Emoji "[del] File $errorFile deleted after completion." "Cyan"
}

# Auto-open folder
Write-Emoji "[d] Opening download folder: $mediaDir" "Cyan"
try {
    Start-Process explorer.exe -ArgumentList $mediaDir
} catch {
    Write-Emoji "[!] Не удалось открыть папку: $_" "Yellow"
}

Write-Emoji "[done] Completed! All indexes processed." "Cyan"
