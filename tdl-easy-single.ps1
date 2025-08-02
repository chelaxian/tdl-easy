# Interrupt handling: clean exit on Ctrl+C
trap [System.OperationCanceledException] {
    Write-Host "`n⚠️ Interrupted by user." -ForegroundColor Yellow
    exit
}

#################################################################################################################################################
# Configuration storage in JSON file (for session state option only)
#################################################################################################################################################
$stateFile = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath "tdl_single_download.json"

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
        telegramMessageUrl = "" 
    }
    Save-Config $empty
}

# Default in-memory values
$telegramMessageUrl = ""
$tdl_path = Split-Path -Parent $MyInvocation.MyCommand.Path  # Use script directory
$downloadLimit = 1    # Single file download
$threads = 4          # Reasonable default
$maxRetries = 1       # Single attempt
$timeoutSeconds = 300 # Timeout for download
$logFile = Join-Path -Path $tdl_path -ChildPath "download_log.txt"
$tempOutputFile = Join-Path -Path $tdl_path -ChildPath "tdl_output.txt"
$tempErrorFile = Join-Path -Path $tdl_path -ChildPath "tdl_error.txt"

# Load existing configuration (for URL only)
$existing = Load-Config
$haveAnySaved = $false
if ($existing -and $existing.telegramMessageUrl -and $existing.telegramMessageUrl.ToString().Trim() -ne "") {
    $haveAnySaved = $true
    $telegramMessageUrl = $existing.telegramMessageUrl
}

$useSaved = $false
if ($haveAnySaved) {
    $attempts = 0
    $maxAttempts = 3
    while ($attempts -lt $maxAttempts) {
        $resp = Read-Host "Type (Yes) to use saved URL ($telegramMessageUrl), (No) to enter a new URL, or (ClearSession) to clear TDL session state"
        switch -Regex ($resp) {
            '^(?i)y(es)?$' { 
                $useSaved = $true 
                break
            }
            '^(?i)n(o)?$' {
                $useSaved = $false
                Clear-Config
                $telegramMessageUrl = ""
                break
            }
            '^(?i)ClearSession$' {
                $tdlSessionDir = Join-Path -Path $env:USERPROFILE -ChildPath ".tdl"
                if (Test-Path $tdlSessionDir) {
                    Write-Host "🗑️ Clearing TDL session state in $tdlSessionDir" -ForegroundColor Cyan
                    Remove-Item -Path $tdlSessionDir -Recurse -Force
                } else {
                    Write-Host "ℹ️ No session state found in $tdlSessionDir" -ForegroundColor Cyan
                }
                $useSaved = $true
                break
            }
            default {
                $attempts++
                if ($attempts -ge $maxAttempts) {
                    Write-Host "ℹ️ Unrecognized response after $maxAttempts attempts. Assuming use saved URL." -ForegroundColor Yellow
                    $useSaved = $true
                    break
                }
                Write-Host "🔴 Unrecognized response. Please type 'Yes', 'No', or 'ClearSession'. ($($maxAttempts - $attempts) attempts remaining)" -ForegroundColor Red
            }
        }
    }
}

# Prompt for Telegram message URL if not using saved
if (-not $useSaved) {
    do {
        Write-Host ""
        Write-Host "╔════════════════════ TELEGRAM POST URL CONFIGURATION ═══════════════════════╗" -ForegroundColor DarkGray
        Write-Host "║ Example: https://t.me/c/12345678/123 (post with the file to download)" -ForegroundColor Gray
        Write-Host "╠────────────────────────────────────────────────────────────────────────────╣" -ForegroundColor DarkGray
        Write-Host "Enter the Telegram post URL" 
        $input = Read-Host
        if ([string]::IsNullOrWhiteSpace($input)) {
            Write-Host "🔴 Error: URL cannot be empty." -ForegroundColor Red
            continue
        }
        if ($input -notmatch '^https?://t\.me/(?:(?:c/\d+/\d+)|(?:s/[A-Za-z0-9_]{5,32}/\d+)|(?:[A-Za-z0-9_]{5,32}/\d+))/?$') {
            Write-Host "🔴 Error: URL must be of form https://t.me/c/12345678/123 or https://t.me/abc/123." -ForegroundColor Red
            continue
        }
        $telegramMessageUrl = $input
        # Save the URL
        $toSave = @{ telegramMessageUrl = $telegramMessageUrl }
        Save-Config $toSave
        break
    } while ($true)
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor DarkGray
}

# Extract chat ID and message ID from URL
$channelId = $null
$messageId = $null
if ($telegramMessageUrl -match '^https?://t\.me/c/(\d+)/(\d+)$') {
    $channelId = $Matches[1]
    $messageId = $Matches[2]
}
if ([string]::IsNullOrWhiteSpace($channelId) -or [string]::IsNullOrWhiteSpace($messageId)) {
    Write-Host "🔴 Error: Failed to extract chat ID or message ID from URL: $telegramMessageUrl" -ForegroundColor Red
    exit
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

# Check TDL authentication
Write-Host "🟡 Checking TDL authentication status..." -ForegroundColor Yellow
if (Test-Path $tempOutputFile) { Remove-Item -Path $tempOutputFile -Force }
if (Test-Path $tempErrorFile) { Remove-Item -Path $tempErrorFile -Force }
$process = Start-Process -FilePath ".\tdl.exe" -ArgumentList "auth status" -NoNewWindow -RedirectStandardOutput $tempOutputFile -RedirectStandardError $tempErrorFile -PassThru
$process | Wait-Process
$authOutput = ""
if (Test-Path $tempOutputFile) { $authOutput += Get-Content $tempOutputFile -Raw }
if (Test-Path $tempErrorFile) { $authOutput += Get-Content $tempErrorFile -Raw }
if ($authOutput -match "not authorized|please login") {
    Write-Host "🔴 TDL is not authorized. Please log in to Telegram." -ForegroundColor Red
    Write-Host "ℹ️ Run the following command in the terminal, follow the prompts to log in, then rerun this script:" -ForegroundColor Cyan
    Write-Host ".\tdl.exe login" -ForegroundColor Gray
    Write-Host "ℹ️ If you need to clear the session state, choose 'ClearSession' at the initial prompt." -ForegroundColor Cyan
    exit
} elseif ($authOutput -match "authorized") {
    Write-Host "🟢 TDL is authorized." -ForegroundColor Green
} else {
    Write-Host "⚠️ Unable to verify TDL authentication status. Proceeding, but login may be required." -ForegroundColor Yellow
    $authOutput | Out-File -FilePath $logFile -Append
}
if (Test-Path $tempOutputFile) { Remove-Item -Path $tempOutputFile -Force }
if (Test-Path $tempErrorFile) { Remove-Item -Path $tempErrorFile -Force }

# Function to stream file contents incrementally
function Stream-FileContents($filePath, $lastPosition, $foregroundColor = "White") {
    if (Test-Path $filePath) {
        $content = Get-Content $filePath -Raw
        if ($content) {
            $lines = $content -split "`n"
            $newLines = $lines[$lastPosition..($lines.Count - 1)]
            foreach ($line in $newLines) {
                if ($line) {
                    Write-Host $line -ForegroundColor $foregroundColor
                }
            }
            return $lines.Count
        }
    }
    return $lastPosition
}

# Download the single file
$downloadCommand = ".\tdl.exe download --dir `"$tdl_path`" --url `"$telegramMessageUrl`" -l $downloadLimit -t $threads"
Write-Host "🟡 Starting download for chat ID: $channelId, message ID: $messageId" -ForegroundColor Yellow
Write-Host "📋 Download Command: $downloadCommand" -ForegroundColor Gray
"[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] Starting download for chat ID: $channelId, message ID: $messageId" | Out-File -FilePath $logFile -Append
$downloadCommand | Out-File -FilePath $logFile -Append

$retryCount = 0
while ($retryCount -lt $maxRetries) {
    try {
        if (Test-Path $tempOutputFile) { Remove-Item -Path $tempOutputFile -Force }
        if (Test-Path $tempErrorFile) { Remove-Item -Path $tempErrorFile -Force }
        $process = Start-Process -FilePath ".\tdl.exe" -ArgumentList "dl -c $channelId -m $messageId --dir `"$tdl_path`" -l $downloadLimit -t $threads" -NoNewWindow -RedirectStandardOutput $tempOutputFile -RedirectStandardError $tempErrorFile -PassThru
        $outputPosition = 0
        $errorPosition = 0
        $startTime = Get-Date
        while (-not $process.HasExited -and ((Get-Date) - $startTime).TotalSeconds -lt $timeoutSeconds) {
            $outputPosition = Stream-FileContents -filePath $tempOutputFile -lastPosition $outputPosition -foregroundColor "White"
            $errorPosition = Stream-FileContents -filePath $tempErrorFile -lastPosition $errorPosition -foregroundColor "Red"
            Start-Sleep -Milliseconds 100
        }
        if (-not $process.HasExited) {
            $process | Stop-Process -Force
            Write-Host "🔴 Timeout reached for download after $timeoutSeconds seconds" -ForegroundColor Red
            throw "Timeout"
        }
        # Capture any remaining output
        $outputPosition = Stream-FileContents -filePath $tempOutputFile -lastPosition $outputPosition -foregroundColor "White"
        $errorPosition = Stream-FileContents -filePath $tempErrorFile -lastPosition $errorPosition -foregroundColor "Red"
        # Combine output and error for logging and processing
        $output = ""
        if (Test-Path $tempOutputFile) { $output += Get-Content $tempOutputFile -Raw }
        if (Test-Path $tempErrorFile) { $output += Get-Content $tempErrorFile -Raw }
        $output | Out-File -FilePath $logFile -Append

        # Check for critical errors
        if ($output -match "Error:.*(Incorrect function|callback|failed to download|not authorized)") {
            Write-Host "🔴 Critical error detected in download output: $output" -ForegroundColor Red
            if ($output -match "not authorized|please login") {
                Write-Host "ℹ️ TDL is not authorized. Please run the following command, follow the prompts to log in, then rerun this script:" -ForegroundColor Cyan
                Write-Host ".\tdl.exe login" -ForegroundColor Gray
                exit
            }
            throw "Critical error in download"
        }

        # Check for downloaded file
        $newFile = Get-ChildItem -Path $tdl_path -File | Where-Object { $_.Name -match "^${channelId}_${messageId}_" -and $_.Length -gt 0 -and $_.Extension -ne ".tmp" }
        if ($newFile) {
            Write-Host "🟢 Successfully downloaded $($newFile.Name) for message ID: $messageId" -ForegroundColor Green
            break
        } else {
            Write-Host "🔴 No file downloaded for message ID: $messageId" -ForegroundColor Red
            throw "No file downloaded"
        }
    } catch {
        Write-Host "🔴 Error executing download command: $_" -ForegroundColor Red
        if (Test-Path $tempOutputFile) { Get-Content $tempOutputFile | Out-File -FilePath $logFile -Append }
        if (Test-Path $tempErrorFile) { Get-Content $tempErrorFile | Out-File -FilePath $logFile -Append }
        $retryCount++
        if ($retryCount -ge $maxRetries) {
            Write-Host "🔴 Exceeded max retries ($maxRetries)" -ForegroundColor Red
            break
        }
        Write-Host "🔶 Retrying download..." -ForegroundColor Yellow
    } finally {
        if (Test-Path $tempOutputFile) { Remove-Item -Path $tempOutputFile -Force }
        if (Test-Path $tempErrorFile) { Remove-Item -Path $tempErrorFile -Force }
    }
}

# Clean up incomplete files
$incompleteFiles = Get-ChildItem -Path $tdl_path -File | Where-Object { $_.Name -match "^${channelId}_${messageId}_.*" -and $_.Length -eq 0 }
foreach ($incompleteFile in $incompleteFiles) {
    Remove-Item -Path $incompleteFile.FullName -Force
    Write-Host "❌ Removed incomplete file $($incompleteFile.Name)" -ForegroundColor Red
}

Write-Host "🎉 Download completed!" -ForegroundColor Cyan
