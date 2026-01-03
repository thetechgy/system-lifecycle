#
# Utils.psm1 - Common utility functions
#
# Usage:
#   Import-Module .\Utils.psm1
#   Test-Administrator -ExitIfNot
#   if (Test-CommandExists npm) { Write-Host "npm is installed" }
#
# Dependencies:
#   - Logging.psm1 (must be imported first by calling script)
#

# Exit codes (matching Linux equivalents)
$Script:ExitCodes = @{
    Success             = 0
    Error               = 1
    InvalidArgs         = 2
    NotAdmin            = 3
    WingetFailed        = 4
    WindowsUpdateFailed = 5
    NpmFailed           = 6
}

<#
.SYNOPSIS
    Gets the exit codes hashtable.

.DESCRIPTION
    Returns a hashtable containing all defined exit codes for use in scripts.

.EXAMPLE
    $codes = Get-ExitCodes
    exit $codes.Success
#>
function Get-ExitCodes {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return $Script:ExitCodes
}

<#
.SYNOPSIS
    Checks if a command exists.

.DESCRIPTION
    Tests whether a command (executable, cmdlet, function, or alias) is available.

.PARAMETER Command
    The command name to check.

.EXAMPLE
    if (Test-CommandExists 'winget') { Write-Host "winget is available" }
#>
function Test-CommandExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    return [bool](Get-Command -Name $Command -ErrorAction SilentlyContinue)
}

<#
.SYNOPSIS
    Checks if running as Administrator.

.DESCRIPTION
    Tests whether the current PowerShell session is running with Administrator
    privileges. Optionally exits the script if not running as Administrator.

.PARAMETER ExitIfNot
    If specified, exits with exit code 3 if not running as Administrator.

.EXAMPLE
    if (Test-Administrator) { Write-Host "Running as admin" }

.EXAMPLE
    Test-Administrator -ExitIfNot
#>
function Test-Administrator {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [switch]$ExitIfNot
    )

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    if ($ExitIfNot -and -not $isAdmin) {
        Write-LogError 'This script must be run as Administrator'
        exit $Script:ExitCodes.NotAdmin
    }

    return $isAdmin
}

<#
.SYNOPSIS
    Displays system information.

.DESCRIPTION
    Retrieves and logs system information including hostname, OS version,
    build number, and current date/time.

.EXAMPLE
    Get-SystemInfo
#>
function Get-SystemInfo {
    [CmdletBinding()]
    param()

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem

        Write-LogInfo "Hostname: $($cs.Name)"
        Write-LogInfo "OS: $($os.Caption)"
        Write-LogInfo "Version: $($os.Version)"
        Write-LogInfo "Build: $($os.BuildNumber)"
        Write-LogInfo "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
    } catch {
        Write-LogWarning "Could not retrieve system information: $_"
    }
}

<#
.SYNOPSIS
    Checks if a system reboot is required.

.DESCRIPTION
    Checks various registry keys to determine if Windows requires a reboot
    to complete pending updates or changes.

.EXAMPLE
    if (Test-RebootRequired) { Write-Host "Reboot required" }
#>
function Test-RebootRequired {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Check Windows Update reboot flag
    $wuReboot = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'

    # Check Component Based Servicing reboot flag
    $cbsReboot = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'

    # Check PendingFileRenameOperations
    $pendingRename = $false
    try {
        $sessionManager = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        $pendingRename = $null -ne $sessionManager
    } catch {
        # Ignore errors reading registry
    }

    # Check SCCM client reboot flag (if SCCM is installed)
    $sccmReboot = $false
    try {
        $sccmUtil = [wmiclass]'\\.\root\ccm\clientsdk:CCM_ClientUtilities'
        $sccmStatus = $sccmUtil.DetermineIfRebootPending()
        $sccmReboot = $sccmStatus.RebootPending
    } catch {
        # SCCM not installed or not accessible
    }

    return ($wuReboot -or $cbsReboot -or $pendingRename -or $sccmReboot)
}

<#
.SYNOPSIS
    Tests if running in Windows Subsystem for Linux.

.DESCRIPTION
    Detects if the script is running inside WSL (Windows Subsystem for Linux).
    This is useful for skipping operations that don't apply to virtualized environments.

.EXAMPLE
    if (Test-IsWSL) { Write-Host "Running in WSL" }
#>
function Test-IsWSL {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Check for WSL-specific environment variables or paths
    if ($env:WSL_DISTRO_NAME -or $env:WSL_INTEROP) {
        return $true
    }

    # Check if /proc/version contains WSL
    if (Test-Path '/proc/version') {
        $procVersion = Get-Content '/proc/version' -ErrorAction SilentlyContinue
        if ($procVersion -match 'microsoft|WSL') {
            return $true
        }
    }

    return $false
}

Export-ModuleMember -Function Get-ExitCodes, Test-CommandExists, Test-Administrator,
    Get-SystemInfo, Test-RebootRequired, Test-IsWSL
