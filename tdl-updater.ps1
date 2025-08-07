<#
    tdl-updater.ps1

    Installs or updates the `tdl.exe` binary from the iyear/tdl GitHub releases.
    Automatically replaces the `$currentVersion` string in this script upon a successful update.
#>

# =============================================================================
# Parameters
# =============================================================================

# Current version of tdl; will be replaced in this file when we update
$currentVersion = "v0.19.0"

# Path where this script is located and where tdl.exe should live
$tdlPath        = $PSScriptRoot

# GitHub "latest release" redirect URL
$latestReleaseUrl = "https://github.com/iyear/tdl/releases/latest"

# Base URL to download specific version zips
$downloadBaseUrl  = "https://github.com/iyear/tdl/releases/download/"

# =============================================================================
# Helpers
# =============================================================================

# Path to the tdl.exe we're managing
$tdlExe = Join-Path $tdlPath 'tdl.exe'

function Write-Info($msg) { Write-Host "ℹ️  $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "⚠️  $msg" -ForegroundColor Yellow }
function Write-ErrorLine($msg) { Write-Host "❌  $msg" -ForegroundColor Red }

# =============================================================================
# Retrieve the latest release tag from GitHub
# =============================================================================
function Get-LatestVersion {
    try {
        Write-Info "Checking GitHub for latest release..."
        $resp = Invoke-WebRequest -Uri $latestReleaseUrl -MaximumRedirection 0 -ErrorAction Stop
        # GitHub will 302 Redirect; the Location header ends in /tagName
        $location = $resp.Headers['Location']
        if (-not $location) {
            # fallback to following redirect
            $resp = Invoke-WebRequest -Uri $latestReleaseUrl -ErrorAction Stop
            $location = $resp.BaseResponse.ResponseUri.AbsoluteUri
        }
        $tag = ($location -split '/')[-1]
        Write-Info "Latest release on GitHub is $tag"
        return $tag
    } catch {
        Write-Warn "Failed to fetch latest release info: $_"
        return $null
    }
}

# =============================================================================
# Download, extract and install the specified version
# =============================================================================
function Update-Tdl {
    param(
        [Parameter(Mandatory)]
        [string]$newVersion
    )

    if (-not $newVersion) {
        Write-ErrorLine "No version supplied to install/update."
        return $false
    }

    $zipUrl     = "$downloadBaseUrl$newVersion/tdl_Windows_64bit.zip"
    $tempZip    = Join-Path $tdlPath 'tdl_update.zip'
    $tempFolder = Join-Path $tdlPath 'tdl_update_tmp'

    try {
        Write-Info "Downloading tdl $newVersion from $zipUrl …"
        Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -ErrorAction Stop
        Write-Info "Archive saved to $tempZip"

        Write-Info "Extracting archive to $tempFolder …"
        if (Test-Path $tempFolder) { Remove-Item $tempFolder -Recurse -Force }
        Expand-Archive -LiteralPath $tempZip -DestinationPath $tempFolder -Force
        Write-Info "Extraction complete."

        Write-Info "Copying new files into $tdlPath …"
        Get-ChildItem -Path $tempFolder -Recurse |
            ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $tdlPath -Force }
        Write-Info "Installation complete."

        Write-Info "Cleaning up temporary files …"
        Remove-Item $tempZip -Force
        Remove-Item $tempFolder -Recurse -Force
        Write-Info "Cleanup done."

        # Open the folder so user can see the new binary
        Start-Process explorer.exe -ArgumentList $tdlPath

        # =============================================================================
        # Rewrite the $currentVersion line in this script to the newly installed version
        # =============================================================================
        $scriptPath = $PSCommandPath
        Write-Info "Updating script version marker in $scriptPath …"
        $pattern     = '^(?<pre>\$currentVersion\s*=\s*")v[\d\.]+(?<post>")'
        $replacement = '${pre}' + $newVersion + '${post}'
        $allText = Get-Content -LiteralPath $scriptPath -Raw
        $newText = $allText -replace $pattern, $replacement
        if ($newText -ne $allText) {
            Set-Content -LiteralPath $scriptPath -Value $newText -Encoding UTF8
            Write-Info "Script version updated to $newVersion."
        } else {
            Write-Warn "Could not locate \$currentVersion line to update."
        }

        return $true
    }
    catch {
        Write-ErrorLine "Update failed: $_"
        # cleanup partial
        if (Test-Path $tempZip)    { Remove-Item $tempZip -Force }
        if (Test-Path $tempFolder) { Remove-Item $tempFolder -Recurse -Force }
        return $false
    }
}

# =============================================================================
# Main logic: decide whether to install/update
# =============================================================================
$latestVersion = Get-LatestVersion

Write-Host ""
Write-Host "Current script version: $currentVersion"
if ($latestVersion) {
    Write-Host "Latest GitHub version:   $latestVersion"
} else {
    Write-Host "Latest GitHub version:   (unavailable)"
}

$needUpdate = $false
if (-not (Test-Path $tdlExe)) {
    Write-Warn "tdl.exe is not present; will install version $($latestVersion ?? $currentVersion)."
    $needUpdate = $true
}
elseif ($latestVersion) {
    try {
        $cmp = [version]($currentVersion.TrimStart('v')) -lt [version]($latestVersion.TrimStart('v'))
        if ($cmp) {
            Write-Warn "A newer version is available: $latestVersion. Beginning update."
            $needUpdate = $true
        } else {
            Write-Info "You already have the latest version ($currentVersion) and tdl.exe is present."
        }
    } catch {
        Write-Warn "Version comparison failed; proceeding to update."
        $needUpdate = $true
    }
} else {
    Write-Warn "Cannot determine latest version; skipping update."
}

if ($needUpdate) {
    $verToUse = $latestVersion ?? $currentVersion
    if (-not (Update-Tdl -newVersion $verToUse)) {
        Write-ErrorLine "tdl install/update failed."
        exit 1
    }
}

Write-Host ""
Write-Info "tdl install/update routine complete."
