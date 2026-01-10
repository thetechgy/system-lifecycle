<#
.SYNOPSIS
    Windows 10/11 System Update Script

.DESCRIPTION
    Performs comprehensive system updates including Windows Update,
    winget packages, optional Chocolatey/Scoop packages, npm global
    packages, PatchMyPC application updates, and vendor-specific
    firmware/driver updates (Dell Command Update, Lenovo Vantage/System
    Update), with logging and error handling.

.PARAMETER DryRun
    Show what would be done without making changes.

.PARAMETER Quiet
    Suppress non-essential output.

.PARAMETER NoNpm
    Skip npm global package updates.

.PARAMETER NoChocolatey
    Skip Chocolatey package updates.

.PARAMETER NoScoop
    Skip Scoop package updates.

.PARAMETER NoPatchMyPC
    Skip PatchMyPC application updates.

.PARAMETER IncludeDrivers
    Include driver updates via Windows Update and vendor tools
    (Dell Command Update, Lenovo Vantage/System Update if installed).

.PARAMETER Clean
    Aggressive cleanup of package caches.

.EXAMPLE
    .\Update-System.ps1
    Full update (Windows Update, winget, chocolatey, scoop, npm)

.EXAMPLE
    .\Update-System.ps1 -DryRun
    Preview changes without making them

.EXAMPLE
    .\Update-System.ps1 -NoChocolatey -NoScoop
    Skip Chocolatey and Scoop updates

.EXAMPLE
    .\Update-System.ps1 -IncludeDrivers
    Include driver updates and vendor firmware (Dell/Lenovo)

.EXAMPLE
    .\Update-System.ps1 -Clean
    Aggressive cache cleanup

.EXAMPLE
    .\Update-System.ps1 -NoPatchMyPC
    Skip PatchMyPC application updates

.NOTES
    Author: Travis McDade
    License: MIT
    Version: 1.1.0
    Requires: PowerShell 5.1+, Windows 10/11, Administrator privileges

    Supported vendor tools:
    - Dell Command Update (dcu-cli.exe)
    - Lenovo System Update (tvsu.exe)
    - Lenovo Commercial Vantage (via COM interface)

.LINK
    https://github.com/thetechgy/system-lifecycle
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [Alias('d')]
    [switch]$DryRun,

    [Parameter()]
    [Alias('q')]
    [switch]$Quiet,

    [Parameter()]
    [Alias('n')]
    [switch]$NoNpm,

    [Parameter()]
    [switch]$NoChocolatey,

    [Parameter()]
    [switch]$NoScoop,

    [Parameter()]
    [switch]$NoPatchMyPC,

    [Parameter()]
    [switch]$IncludeDrivers,

    [Parameter()]
    [switch]$Clean
)

# -----------------------------------------------------------------------------
# Script Configuration
# -----------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$Script:Version = '1.1.0'
$Script:ScriptName = $MyInvocation.MyCommand.Name
$Script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:LibDir = Join-Path (Split-Path -Parent $Script:ScriptDir) 'lib'

# Exit code tracker (set by functions, used at exit)
$Script:ExitCode = 0

# -----------------------------------------------------------------------------
# Import Modules
# -----------------------------------------------------------------------------

Import-Module (Join-Path $Script:LibDir 'Colors.psm1') -Force
Import-Module (Join-Path $Script:LibDir 'Logging.psm1') -Force
Import-Module (Join-Path $Script:LibDir 'Utils.psm1') -Force
Import-Module (Join-Path $Script:LibDir 'VersionCheck.psm1') -Force

$ExitCodes = Get-ExitCodes

# -----------------------------------------------------------------------------
# Windows Update Functions
# -----------------------------------------------------------------------------

function Update-WindowsSystem {
    [CmdletBinding()]
    param(
        [switch]$DryRun,
        [switch]$IncludeDrivers
    )

    Write-Section 'Windows Update'

    # Check for PSWindowsUpdate module
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-LogInfo 'PSWindowsUpdate module not found, installing...'
        if (-not $DryRun) {
            try {
                Install-Module -Name PSWindowsUpdate -Force -Scope CurrentUser -ErrorAction Stop
                Write-LogSuccess 'PSWindowsUpdate module installed'
            } catch {
                Write-LogWarning "Could not install PSWindowsUpdate module: $_"
                Write-LogWarning 'Skipping Windows Update (manual installation required)'
                return
            }
        } else {
            Write-LogInfo '[DRY-RUN] Would install PSWindowsUpdate module'
        }
    }

    try {
        Import-Module PSWindowsUpdate -ErrorAction Stop
    } catch {
        Write-LogWarning "Could not import PSWindowsUpdate module: $_"
        Write-LogWarning 'Skipping Windows Update'
        return
    }

    if ($DryRun) {
        Write-LogInfo '[DRY-RUN] Would check for Windows updates'
        Write-LogInfo 'Checking for available updates...'

        try {
            $updates = Get-WindowsUpdate -MicrosoftUpdate -ErrorAction SilentlyContinue
            if ($IncludeDrivers) {
                $driverUpdates = Get-WindowsUpdate -UpdateType Driver -ErrorAction SilentlyContinue
                if ($driverUpdates) {
                    $updates = @($updates) + @($driverUpdates)
                }
            }

            if ($updates -and $updates.Count -gt 0) {
                Write-LogInfo "Available updates ($($updates.Count)):"
                foreach ($update in $updates) {
                    Write-LogInfo "  - $($update.Title)"
                }
            } else {
                Write-LogSuccess 'No updates available'
            }
        } catch {
            Write-LogWarning "Could not check for updates: $_"
        }
        return
    }

    Write-LogInfo 'Checking for Windows updates...'
    try {
        $params = @{
            MicrosoftUpdate = $true
            AcceptAll       = $true
            IgnoreReboot    = $true
        }

        if ($IncludeDrivers) {
            Write-LogInfo 'Including driver updates...'
            # Run driver updates first
            try {
                $driverResult = Get-WindowsUpdate -UpdateType Driver -AcceptAll -Install -IgnoreReboot -ErrorAction SilentlyContinue
                if ($driverResult) {
                    Write-LogSuccess 'Driver updates applied'
                }
            } catch {
                Write-LogWarning "Driver updates encountered issues: $_"
            }
        }

        $result = Install-WindowsUpdate @params -ErrorAction SilentlyContinue
        if ($result) {
            Write-LogSuccess "Windows updates completed ($($result.Count) updates applied)"
        } else {
            Write-LogSuccess 'Windows Update completed (system is up to date)'
        }
    } catch {
        Write-LogError "Windows Update failed: $_"
        $Script:ExitCode = $ExitCodes.WindowsUpdateFailed
    }
}

# -----------------------------------------------------------------------------
# Vendor Firmware/Driver Functions
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Gets the system manufacturer.

.DESCRIPTION
    Returns the manufacturer name from WMI (e.g., "Dell Inc.", "LENOVO").
#>
function Get-SystemManufacturer {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        return $cs.Manufacturer
    } catch {
        return $null
    }
}

<#
.SYNOPSIS
    Finds Dell Command Update CLI executable.

.DESCRIPTION
    Searches common installation paths for dcu-cli.exe.
#>
function Find-DellCommandUpdate {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $searchPaths = @(
        "${env:ProgramFiles}\Dell\CommandUpdate\dcu-cli.exe",
        "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe",
        "${env:ProgramW6432}\Dell\CommandUpdate\dcu-cli.exe"
    )

    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    return $null
}

<#
.SYNOPSIS
    Updates Dell system using Dell Command Update.

.DESCRIPTION
    Runs Dell Command Update CLI to install BIOS, firmware, and driver updates.
#>
function Update-DellFirmware {
    [CmdletBinding()]
    param(
        [switch]$DryRun
    )

    Write-Section 'Dell Command Update'

    $dcuPath = Find-DellCommandUpdate
    if (-not $dcuPath) {
        Write-LogInfo 'Dell Command Update is not installed, skipping'
        return
    }

    Write-LogInfo "Found Dell Command Update: $dcuPath"

    if ($DryRun) {
        Write-LogInfo '[DRY-RUN] Would run: dcu-cli.exe /scan'
        Write-LogInfo 'Scanning for available updates...'
        try {
            $scanResult = & $dcuPath /scan 2>&1
            foreach ($line in $scanResult) {
                if (Test-ShouldLogLine $line) {
                    Write-LogInfo "  $line"
                }
            }
        } catch {
            Write-LogWarning "Could not scan for updates: $_"
        }
        return
    }

    Write-LogInfo 'Scanning for Dell updates...'
    try {
        # First scan to see what's available
        $scanResult = & $dcuPath /scan 2>&1
        foreach ($line in $scanResult) {
            if (Test-ShouldLogLine $line) {
                Write-LogInfo "  $line"
            }
        }

        Write-LogInfo 'Applying Dell updates (BIOS, drivers, firmware)...'
        # Apply all updates, reboot handled separately
        # /silent = no GUI, /reboot=disable = don't auto-reboot
        $applyResult = & $dcuPath /applyUpdates -silent -reboot=disable 2>&1
        foreach ($line in $applyResult) {
            if (Test-ShouldLogLine $line) {
                Write-LogInfo "  $line"
            }
        }

        Write-LogSuccess 'Dell Command Update completed'
    } catch {
        Write-LogWarning "Dell Command Update encountered issues: $_"
    }
}

<#
.SYNOPSIS
    Finds Lenovo System Update executable.

.DESCRIPTION
    Searches common installation paths for Lenovo System Update (tvsu.exe).
#>
function Find-LenovoSystemUpdate {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $searchPaths = @(
        "${env:ProgramFiles}\Lenovo\System Update\tvsu.exe",
        "${env:ProgramFiles(x86)}\Lenovo\System Update\tvsu.exe",
        "${env:ProgramW6432}\Lenovo\System Update\tvsu.exe"
    )

    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    return $null
}

<#
.SYNOPSIS
    Finds Lenovo Commercial Vantage or Vantage executable.

.DESCRIPTION
    Searches for Lenovo Vantage (consumer) or Commercial Vantage installation.
    Returns path to the CLI tool if available.
#>
function Find-LenovoVantage {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $result = @{
        Found = $false
        Type  = $null
        Path  = $null
    }

    # Check for Commercial Vantage (has better CLI support)
    $commercialPaths = @(
        "${env:ProgramFiles}\Lenovo\Commercial Vantage\LenovoVantageService.exe",
        "${env:ProgramFiles(x86)}\Lenovo\Commercial Vantage\LenovoVantageService.exe"
    )

    foreach ($path in $commercialPaths) {
        if (Test-Path $path) {
            $result.Found = $true
            $result.Type = 'Commercial'
            $result.Path = Split-Path -Parent $path
            return $result
        }
    }

    # Check for consumer Vantage (UWP app - limited CLI)
    $vantagePackage = Get-AppxPackage -Name '*LenovoVantage*' -ErrorAction SilentlyContinue
    if ($vantagePackage) {
        $result.Found = $true
        $result.Type = 'Consumer'
        $result.Path = $vantagePackage.InstallLocation
        return $result
    }

    return $result
}

<#
.SYNOPSIS
    Updates Lenovo system using System Update or Vantage.

.DESCRIPTION
    Runs Lenovo System Update or Commercial Vantage to install BIOS,
    firmware, and driver updates.
#>
function Update-LenovoFirmware {
    [CmdletBinding()]
    param(
        [switch]$DryRun
    )

    Write-Section 'Lenovo System Update'

    # Try Lenovo System Update first (preferred for automation)
    $tvsuPath = Find-LenovoSystemUpdate
    if ($tvsuPath) {
        Write-LogInfo "Found Lenovo System Update: $tvsuPath"

        if ($DryRun) {
            Write-LogInfo '[DRY-RUN] Would run: tvsu.exe /CM -search A -action LIST'
            Write-LogInfo 'Scanning for available updates...'
            try {
                # List available updates
                $scanResult = & $tvsuPath /CM -search A -action LIST 2>&1
                foreach ($line in $scanResult) {
                    if (Test-ShouldLogLine $line) {
                        Write-LogInfo "  $line"
                    }
                }
            } catch {
                Write-LogWarning "Could not scan for updates: $_"
            }
            return
        }

        Write-LogInfo 'Scanning and installing Lenovo updates...'
        try {
            # /CM = Command Mode
            # -search A = Search all packages
            # -action INSTALL = Download and install
            # -includerebootpackages 3 = Include reboot packages, defer reboot
            # -noreboot = Don't reboot automatically
            $installResult = & $tvsuPath /CM -search A -action INSTALL -includerebootpackages 3 -noreboot 2>&1
            foreach ($line in $installResult) {
                if (Test-ShouldLogLine $line) {
                    Write-LogInfo "  $line"
                }
            }
            Write-LogSuccess 'Lenovo System Update completed'
        } catch {
            Write-LogWarning "Lenovo System Update encountered issues: $_"
        }
        return
    }

    # Fall back to Vantage
    $vantage = Find-LenovoVantage
    if ($vantage.Found) {
        Write-LogInfo "Found Lenovo Vantage ($($vantage.Type)): $($vantage.Path)"

        if ($vantage.Type -eq 'Commercial') {
            # Commercial Vantage has PowerShell module support
            if ($DryRun) {
                Write-LogInfo '[DRY-RUN] Would trigger Lenovo Commercial Vantage update check'
                return
            }

            Write-LogInfo 'Triggering Lenovo Commercial Vantage update...'
            try {
                # Try to use the Commercial Vantage scheduled task
                $task = Get-ScheduledTask -TaskName '*Lenovo*Update*' -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($task) {
                    Start-ScheduledTask -TaskName $task.TaskName
                    Write-LogSuccess 'Lenovo Commercial Vantage update triggered'
                    Write-LogInfo 'Note: Updates will run in background. Check Vantage app for status.'
                } else {
                    Write-LogWarning 'Could not find Lenovo Vantage scheduled task'
                    Write-LogInfo 'Please run Lenovo Commercial Vantage manually to check for updates'
                }
            } catch {
                Write-LogWarning "Could not trigger Vantage update: $_"
            }
        } else {
            # Consumer Vantage - UWP app with limited automation
            Write-LogInfo 'Lenovo Vantage (consumer) detected'
            Write-LogInfo 'Consumer Vantage requires manual interaction for updates'
            Write-LogInfo 'Please open Lenovo Vantage app to check for driver/firmware updates'
        }
        return
    }

    Write-LogInfo 'No Lenovo update tools found, skipping'
    Write-LogInfo 'Install Lenovo System Update or Lenovo Vantage for firmware updates'
}

<#
.SYNOPSIS
    Updates vendor-specific firmware and drivers.

.DESCRIPTION
    Detects the system manufacturer and runs the appropriate vendor
    update tool (Dell Command Update, Lenovo System Update/Vantage).
#>
function Update-VendorFirmware {
    [CmdletBinding()]
    param(
        [switch]$DryRun
    )

    $manufacturer = Get-SystemManufacturer
    Write-LogInfo "System manufacturer: $manufacturer"

    if ($manufacturer -match 'Dell') {
        Update-DellFirmware -DryRun:$DryRun
    } elseif ($manufacturer -match 'Lenovo') {
        Update-LenovoFirmware -DryRun:$DryRun
    } else {
        Write-LogInfo "No vendor-specific update tool available for: $manufacturer"
        Write-LogInfo 'Driver updates will be handled by Windows Update only'
    }
}

# -----------------------------------------------------------------------------
# PatchMyPC Functions
# -----------------------------------------------------------------------------

<#
.SYNOPSIS
    Finds PatchMyPC Home Updater executable.

.DESCRIPTION
    Searches common installation paths for PatchMyPC Home Updater (free version).
    Checks Program Files first, then falls back to portable/legacy locations.
#>
function Find-PatchMyPC {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Common installation paths for PatchMyPC Home Updater (free version)
    $searchPaths = @(
        # Installed Home Updater (primary - typical installation path)
        "${env:ProgramFiles}\Patch My PC\Patch My PC Home Updater\PatchMyPC-HomeUpdater.exe",
        "${env:ProgramFiles(x86)}\Patch My PC\Patch My PC Home Updater\PatchMyPC-HomeUpdater.exe",
        # Portable/legacy paths (fallback for older portable versions)
        "$env:USERPROFILE\Downloads\PatchMyPC.exe",
        "$env:LOCALAPPDATA\PatchMyPC\PatchMyPC.exe",
        "C:\PatchMyPC\PatchMyPC.exe"
    )

    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    # Also check if PatchMyPC is in PATH (either name)
    $inPath = Get-Command -Name 'PatchMyPC-HomeUpdater.exe', 'PatchMyPC.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($inPath) {
        return $inPath.Source
    }

    return $null
}

<#
.SYNOPSIS
    Updates applications using PatchMyPC Home Updater.

.DESCRIPTION
    Runs PatchMyPC Home Updater to scan for and install application updates.
    Uses CLI switches /auto and /silent for automated operation.

.PARAMETER DryRun
    Show what would be done without making changes.

.PARAMETER Skip
    Skip PatchMyPC updates entirely.
#>
function Update-PatchMyPC {
    [CmdletBinding()]
    param(
        [switch]$DryRun,
        [switch]$Skip
    )

    if ($Skip) {
        return
    }

    $patchMyPCPath = Find-PatchMyPC
    if (-not $patchMyPCPath) {
        # Silently skip if not installed (matches pattern of Chocolatey/Scoop)
        return
    }

    Write-Section 'PatchMyPC'

    Write-LogInfo "Found PatchMyPC: $patchMyPCPath"

    if ($DryRun) {
        Write-LogInfo '[DRY-RUN] Would run: PatchMyPC.exe /auto /silent'
        Write-LogInfo 'PatchMyPC would scan for and install application updates'
        return
    }

    Write-LogInfo 'Scanning for application updates with PatchMyPC...'
    try {
        # /auto - Automatically download and install updates
        # /silent - Run without GUI interaction
        $result = & $patchMyPCPath /auto /silent 2>&1
        foreach ($line in $result) {
            if (Test-ShouldLogLine $line) {
                Write-LogInfo "  $line"
            }
        }
        Write-LogSuccess 'PatchMyPC updates completed'
    } catch {
        Write-LogWarning "PatchMyPC encountered issues: $_"
    }
}

# -----------------------------------------------------------------------------
# Winget Functions
# -----------------------------------------------------------------------------

function Update-WingetPackages {
    [CmdletBinding()]
    param(
        [switch]$DryRun
    )

    Write-Section 'Winget Packages'

    if (-not (Test-CommandExists 'winget')) {
        Write-LogInfo 'winget is not installed, skipping winget updates'
        return
    }

    if ($DryRun) {
        Write-LogInfo '[DRY-RUN] Would run: winget upgrade --all'
        Write-LogInfo 'Packages that would be upgraded:'
        try {
            $upgradeList = winget upgrade --include-unknown 2>&1
            foreach ($line in $upgradeList) {
                Write-LogInfo "  $line"
            }
        } catch {
            Write-LogWarning "Could not check for updates: $_"
        }
        return
    }

    Write-LogInfo 'Updating winget packages...'
    try {
        # Stream output in real-time instead of buffering (prevents appearing hung)
        # --disable-interactivity prevents any prompts that could hang the script
        winget upgrade --all --silent --disable-interactivity --accept-package-agreements --accept-source-agreements 2>&1 |
            ForEach-Object {
                if (Test-ShouldLogLine $_) {
                    Write-LogInfo "  $_"
                }
            }
        Write-LogSuccess 'Winget packages updated'
    } catch {
        Write-LogWarning "Some winget packages could not be updated: $_"
    }
}

# -----------------------------------------------------------------------------
# Chocolatey Functions
# -----------------------------------------------------------------------------

function Update-ChocolateyPackages {
    [CmdletBinding()]
    param(
        [switch]$DryRun,
        [switch]$Skip
    )

    if ($Skip) {
        return
    }

    if (-not (Test-CommandExists 'choco')) {
        return
    }

    Write-Section 'Chocolatey Packages'

    if ($DryRun) {
        Write-LogInfo '[DRY-RUN] Would run: choco upgrade all -y'
        Write-LogInfo 'Outdated packages:'
        try {
            choco outdated --no-progress 2>&1 | ForEach-Object {
                if (Test-ShouldLogLine $_) {
                    Write-LogInfo "  $_"
                }
            }
        } catch {
            Write-LogWarning "Could not check for outdated packages: $_"
        }
        return
    }

    Write-LogInfo 'Updating Chocolatey packages...'
    try {
        # Stream output in real-time instead of buffering
        choco upgrade all -y --no-progress 2>&1 | ForEach-Object {
            if (Test-ShouldLogLine $_) {
                Write-LogInfo "  $_"
            }
        }
        Write-LogSuccess 'Chocolatey packages updated'
    } catch {
        Write-LogWarning "Some Chocolatey packages could not be updated: $_"
    }
}

# -----------------------------------------------------------------------------
# Scoop Functions
# -----------------------------------------------------------------------------

function Update-ScoopPackages {
    [CmdletBinding()]
    param(
        [switch]$DryRun,
        [switch]$Skip
    )

    if ($Skip) {
        return
    }

    if (-not (Test-CommandExists 'scoop')) {
        return
    }

    Write-Section 'Scoop Packages'

    if ($DryRun) {
        Write-LogInfo '[DRY-RUN] Would run: scoop update *'
        Write-LogInfo 'Package status:'
        try {
            scoop status 2>&1 | ForEach-Object {
                if (Test-ShouldLogLine $_) {
                    Write-LogInfo "  $_"
                }
            }
        } catch {
            Write-LogWarning "Could not check package status: $_"
        }
        return
    }

    Write-LogInfo 'Updating Scoop...'
    try {
        # Stream output in real-time instead of buffering
        # Update Scoop itself first
        scoop update 2>&1 | ForEach-Object {
            if (Test-ShouldLogLine $_) {
                Write-LogInfo "  $_"
            }
        }

        # Update all packages
        Write-LogInfo 'Updating Scoop packages...'
        scoop update * 2>&1 | ForEach-Object {
            if (Test-ShouldLogLine $_) {
                Write-LogInfo "  $_"
            }
        }
        Write-LogSuccess 'Scoop packages updated'
    } catch {
        Write-LogWarning "Some Scoop packages could not be updated: $_"
    }
}

# -----------------------------------------------------------------------------
# NPM Functions
# -----------------------------------------------------------------------------

function Update-NpmPackages {
    [CmdletBinding()]
    param(
        [switch]$DryRun,
        [switch]$Skip
    )

    if ($Skip) {
        return
    }

    if (-not (Test-CommandExists 'npm')) {
        return
    }

    Write-Section 'NPM Global Packages'

    Write-LogInfo 'Checking for outdated npm global packages...'
    $outdated = $null
    try {
        $outdated = npm outdated -g --parseable 2>$null
    } catch {
        # Ignore errors from npm outdated
    }

    if (-not $outdated) {
        Write-LogSuccess 'All npm global packages are up to date'
        return
    }

    Write-LogInfo 'Outdated packages found:'
    foreach ($line in $outdated) {
        if (Test-ShouldLogLine $line) {
            Write-LogInfo "  $line"
        }
    }

    if ($DryRun) {
        Write-LogInfo '[DRY-RUN] Would run: npm update -g'
        return
    }

    Write-LogInfo 'Updating npm global packages...'
    try {
        # Stream output in real-time instead of buffering
        npm update -g 2>&1 | ForEach-Object {
            if (Test-ShouldLogLine $_) {
                Write-LogInfo "  $_"
            }
        }
        Write-LogSuccess 'npm global packages updated'
    } catch {
        Write-LogWarning "Some npm packages could not be updated: $_"
        $Script:ExitCode = $ExitCodes.NpmFailed
    }
}

# -----------------------------------------------------------------------------
# Cleanup Functions
# -----------------------------------------------------------------------------

function Invoke-Cleanup {
    [CmdletBinding()]
    param(
        [switch]$DryRun,
        [switch]$Aggressive
    )

    Write-Section 'Cleanup'

    if ($DryRun) {
        if ($Aggressive) {
            Write-LogInfo '[DRY-RUN] Would clear all package caches'
        } else {
            Write-LogInfo '[DRY-RUN] Would clear temporary package caches'
        }
        return
    }

    # Chocolatey cache cleanup
    if (Test-CommandExists 'choco') {
        Write-LogInfo 'Cleaning Chocolatey cache...'
        try {
            if ($Aggressive) {
                # Note: choco cache command may vary by version
                $null = choco cache remove -y 2>&1
            }
            Write-LogSuccess 'Chocolatey cache cleaned'
        } catch {
            Write-LogWarning 'Could not clean Chocolatey cache'
        }
    }

    # Scoop cache cleanup
    if (Test-CommandExists 'scoop') {
        Write-LogInfo 'Cleaning Scoop cache...'
        try {
            $null = scoop cache rm * 2>&1
            if ($Aggressive) {
                $null = scoop cleanup * 2>&1
            }
            Write-LogSuccess 'Scoop cache cleaned'
        } catch {
            Write-LogWarning 'Could not clean Scoop cache'
        }
    }

    # npm cache cleanup
    if (Test-CommandExists 'npm') {
        Write-LogInfo 'Cleaning npm cache...'
        try {
            if ($Aggressive) {
                $null = npm cache clean --force 2>&1
            } else {
                $null = npm cache verify 2>&1
            }
            Write-LogSuccess 'npm cache cleaned'
        } catch {
            Write-LogWarning 'Could not clean npm cache'
        }
    }

    # Windows temp files (aggressive mode only)
    if ($Aggressive) {
        Write-LogInfo 'Cleaning Windows temp files...'
        try {
            $tempPaths = @(
                $env:TEMP,
                "$env:LOCALAPPDATA\Temp"
            )
            foreach ($tempPath in $tempPaths) {
                if (Test-Path $tempPath) {
                    Get-ChildItem -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue |
                        Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
                        Remove-Item -Force -ErrorAction SilentlyContinue
                }
            }
            Write-LogSuccess 'Temp files cleaned'
        } catch {
            Write-LogWarning 'Could not clean all temp files'
        }
    }

    Write-LogSuccess 'Cache cleanup completed'
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

function Main {
    # Version check first (before anything else)
    Test-ForUpdates

    # Require administrator
    $null = Test-Administrator -ExitIfNot

    # Initialize logging
    Initialize-Logging -ScriptName 'Update-System' -Quiet:$Quiet

    Write-LogInfo 'Starting system update...'
    Write-LogInfo "Dry-run mode: $DryRun"
    Write-LogInfo "Skip Chocolatey: $NoChocolatey"
    Write-LogInfo "Skip Scoop: $NoScoop"
    Write-LogInfo "Skip npm: $NoNpm"
    Write-LogInfo "Include drivers/firmware: $IncludeDrivers"
    Write-LogInfo "Aggressive cleanup: $Clean"
    Write-LogInfo "Skip PatchMyPC: $NoPatchMyPC"

    Write-Section 'System Information'
    Get-SystemInfo

    # Windows Update (primary)
    Update-WindowsSystem -DryRun:$DryRun -IncludeDrivers:$IncludeDrivers

    # Vendor-specific firmware/drivers (Dell, Lenovo)
    if ($IncludeDrivers) {
        Update-VendorFirmware -DryRun:$DryRun
    }

    # Package managers
    Update-WingetPackages -DryRun:$DryRun
    Update-ChocolateyPackages -DryRun:$DryRun -Skip:$NoChocolatey
    Update-ScoopPackages -DryRun:$DryRun -Skip:$NoScoop
    Update-NpmPackages -DryRun:$DryRun -Skip:$NoNpm
    Update-PatchMyPC -DryRun:$DryRun -Skip:$NoPatchMyPC

    # Cleanup
    Invoke-Cleanup -DryRun:$DryRun -Aggressive:$Clean

    Write-Section 'Update Complete'

    # Check for reboot requirement
    if (Test-RebootRequired) {
        Write-LogWarning 'System reboot is required to complete updates'
    }

    # Final status
    $logFile = Get-LogFilePath
    if ($logFile) {
        Write-LogInfo "Log saved to: $logFile"
    }

    if ($Script:ExitCode -eq 0) {
        Write-LogSuccess 'Update completed successfully'
    } else {
        Write-LogError "Update completed with errors (exit code: $Script:ExitCode)"
    }

    exit $Script:ExitCode
}

# Run main
Main
