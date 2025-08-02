# Parameters
$currentVersion = "v0.19.0"  # Current version of tdl, to be updated if a newer version is found
$tdlPath = $PSScriptRoot     # Path where the script is running, used as the target for update
$latestReleaseUrl = "https://github.com/iyear/tdl/releases/latest"
$downloadBaseUrl = "https://github.com/iyear/tdl/releases/download/"

# Helper: path to expected executable
$tdlExe = Join-Path $tdlPath 'tdl.exe'

# Function to get the latest version from GitHub
function Get-LatestVersion {
    try {
        $response = Invoke-WebRequest -Uri $latestReleaseUrl -UseBasicParsing -ErrorAction Stop
        $latestVersion = ($response.BaseResponse.ResponseUri -split '/' | Select-Object -Last 1)
        return $latestVersion  # Includes leading 'v'
    } catch {
        Write-Error "❌ Failed to fetch latest version info: $_"
        return $null
    }
}

# Function to download and extract the update
function Update-Tdl {
    param ([string]$newVersion)

    if (-not $newVersion) {
        Write-Error "❌ No version provided to update."
        return $false
    }

    $downloadUrl = "$downloadBaseUrl$newVersion/tdl_Windows_64bit.zip"
    $tempZip = Join-Path $tdlPath 'tdl_update.zip'
    $tempExtract = Join-Path $tdlPath 'tdl_update_temp'

    try {
        Write-Host "⬇️ Downloading update for version $newVersion..."
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -ErrorAction Stop
        Write-Host "✅ Downloaded update archive to $tempZip"

        Write-Host "📦 Extracting update..."
        if (Test-Path $tempExtract) { Remove-Item -Path $tempExtract -Recurse -Force }
        Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force
        Write-Host "✅ Extracted update to temporary folder"

        Write-Host "🛠 Replacing files in current directory..."
        Get-ChildItem -Path $tempExtract -Recurse | Copy-Item -Destination $tdlPath -Force -Recurse
        Write-Host "✅ Replacement complete"

        Write-Host "🧹 Cleaning up temporary files..."
        Remove-Item -Path $tempZip -Force
        Remove-Item -Path $tempExtract -Recurse -Force
        Write-Host "✅ Cleanup done"

        Write-Host "✅ Update to version $newVersion completed successfully!"

        # Auto-open folder with updated binary
        Write-Host "📂 Opening updated folder: $tdlPath" -ForegroundColor Cyan
        try {
            Start-Process explorer.exe -ArgumentList $tdlPath
        } catch {
            Write-Host "⚠️ Failed to open folder: $_" -ForegroundColor Yellow
        }

        # Update the version in the script file (replace only the value inside quotes)
        $pattern = '(\$currentVersion\s*=\s*")v[\d\.]+(")'
        $replacement = '$1' + $newVersion + '$2'
        (Get-Content $PSCommandPath) -replace $pattern, $replacement | Set-Content $PSCommandPath

        return $true
    } catch {
        Write-Error "❌ Update failed: $_"
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
    Write-Host "🟡 tdl.exe not found in $tdlPath. Will download/install latest version."
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
        Write-Host "🟡 A newer version ($latestVersion) is available. Updating now..."
        $needUpdate = $true
    } elseif ($tdlMissing) {
        Write-Host "🟡 Binary missing but version marker is current. Proceeding to download $latestVersion..."
        $needUpdate = $true
    } else {
        Write-Host "✅ Version is up-to-date and tdl.exe exists."
    }
} else {
    if ($tdlMissing) {
        Write-Host "🟡 Unable to determine latest version from GitHub, but tdl.exe is missing - trying to download current version listed ($currentVersion)..."
        $needUpdate = $true
    } else {
        Write-Host "ℹ️ Unable to retrieve latest version information, but tdl.exe is present. Skipping update."
    }
}

if ($needUpdate -and $latestVersion) {
    $success = Update-Tdl -newVersion $latestVersion
    if (-not $success) {
        Write-Error "❌ Update failed."
    } else {
        Write-Host "✅ Update process finished." 
    }
} elseif ($needUpdate -and -not $latestVersion) {
    # Try fallback to currentVersion if latest unknown
    $success = Update-Tdl -newVersion $currentVersion
    if (-not $success) {
        Write-Error "❌ Update from fallback version failed."
    } else {
        Write-Host "✅ Fallback update process finished."
    }
}

Write-Host "✅ Update check completed."
