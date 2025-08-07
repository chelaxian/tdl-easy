# Simple colored output function
function Write-Emoji {
    param(
        [string]$Text,
        [string]$Color = "White"
    )
    Write-Host $Text -ForegroundColor $Color
}

# Parameters
$currentVersion = "v0.19.1"  # Current version of tdl, to be updated if a newer version is found
$tdlPath = $PSScriptRoot     # Path where the script is running, used as the target for update
$latestReleaseUrl = "https://github.com/iyear/tdl/releases/latest"
$downloadBaseUrl = "https://github.com/iyear/tdl/releases/download/"

# Helper: path to expected executable
$tdlExe = Join-Path $tdlPath 'tdl.exe'

# Function to get the latest version from GitHub
function Get-LatestVersion {
    try {
        $response = Invoke-WebRequest -Uri $latestReleaseUrl -ErrorAction Stop
        $latestVersion = ($response.BaseResponse.ResponseUri -split '/' | Select-Object -Last 1)
        return $latestVersion  # Includes leading 'v'
    } catch {
        Write-Emoji "[x] Failed to fetch latest version info: $_" "Red"
        return $null
    }
}

# Function to download and extract the update
function Update-Tdl {
    param ([string]$newVersion)

    if (-not $newVersion) {
        Write-Emoji "[x] No version provided to update." "Red"
        return $false
    }

    $downloadUrl = "$downloadBaseUrl$newVersion/tdl_Windows_64bit.zip"
    $tempZip = Join-Path $tdlPath 'tdl_update.zip'
    $tempExtract = Join-Path $tdlPath 'tdl_update_temp'

    try {
        Write-Emoji "[*] Downloading update for version $newVersion..." "Yellow"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -ErrorAction Stop
        Write-Emoji "[ok] Downloaded update archive to $tempZip" "Green"

        Write-Emoji "[*] Extracting update..." "Yellow"
        if (Test-Path $tempExtract) { Remove-Item -Path $tempExtract -Recurse -Force }
        Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force
        Write-Emoji "[ok] Extracted update to temporary folder" "Green"

        Write-Emoji "[*] Replacing files in current directory..." "Yellow"
        Get-ChildItem -Path $tempExtract -Recurse | Copy-Item -Destination $tdlPath -Force -Recurse
        Write-Emoji "[ok] Replacement complete" "Green"

        Write-Emoji "[*] Cleaning up temporary files..." "Yellow"
        Remove-Item -Path $tempZip -Force
        Remove-Item -Path $tempExtract -Recurse -Force
        Write-Emoji "[ok] Cleanup done" "Green"

        Write-Emoji "[ok] Update to version $newVersion completed successfully!" "Green"

        # Auto-open folder with updated binary
        Write-Emoji "[d] Opening updated folder: $tdlPath" "Cyan"
        try {
            Start-Process explorer.exe -ArgumentList $tdlPath
        } catch {
            Write-Emoji "[!] Failed to open folder: $_" "Yellow"
        }

        # Update the version in the script file (replace only the value inside quotes)
        $pattern = '(\$currentVersion\s*=\s*")v[\d\.]+(")'
        $replacement = '$1' + $newVersion + '$2'
        (Get-Content $PSCommandPath -Encoding UTF8) -replace $pattern, $replacement | Set-Content $PSCommandPath -Encoding UTF8

        return $true
    } catch {
        Write-Emoji "[x] Update failed: $_" "Red"
        # cleanup partial if exists
        if (Test-Path $tempZip) { Remove-Item -Path $tempZip -Force }
        if (Test-Path $tempExtract) { Remove-Item -Path $tempExtract -Recurse -Force }
        return $false
    }
}

# Check for updates / presence of binary
$latestVersion = Get-LatestVersion
Write-Host "Current version: $currentVersion"
Write-Host "Latest version: $latestVersion"

$tdlMissing = -not (Test-Path $tdlExe)
if ($tdlMissing) {
    Write-Emoji "[*] tdl.exe not found in $tdlPath. Will download/install latest version." "Yellow"
}

$needUpdate = $false
if ($latestVersion) {
    $versionCompare = {
        param($a, $b)
        try {
            return [version]($a -replace '^v', '') -lt [version]($b -replace '^v', '')
        } catch {
            return $true  # if parsing fails, be conservative and update
        }
    }

    if (&$versionCompare $currentVersion $latestVersion) {
        Write-Emoji "[*] A newer version ($latestVersion) is available. Updating now..." "Yellow"
        $needUpdate = $true
    } elseif ($tdlMissing) {
        Write-Emoji "[*] Binary missing but version marker is current. Proceeding to download $latestVersion..." "Yellow"
        $needUpdate = $true
    } else {
        Write-Emoji "[ok] Version is up-to-date and tdl.exe exists." "Green"
    }
} else {
    if ($tdlMissing) {
        Write-Emoji "[*] Unable to determine latest version from GitHub, but tdl.exe is missing - trying to download current version listed ($currentVersion)..." "Yellow"
        $needUpdate = $true
    } else {
        Write-Emoji "[i] Unable to retrieve latest version information, but tdl.exe is present. Skipping update." "Cyan"
    }
}

if ($needUpdate -and $latestVersion) {
    $success = Update-Tdl -newVersion $latestVersion
    if (-not $success) {
        Write-Emoji "[x] Update failed." "Red"
    } else {
        Write-Emoji "[ok] Update process finished." "Green"
    }
} elseif ($needUpdate -and -not $latestVersion) {
    # Try fallback to currentVersion if latest unknown
    $success = Update-Tdl -newVersion $currentVersion
    if (-not $success) {
        Write-Emoji "[x] Update from fallback version failed." "Red"
    } else {
        Write-Emoji "[ok] Fallback update process finished." "Green"
    }
}

Write-Emoji "[ok] Update check completed." "Green"
