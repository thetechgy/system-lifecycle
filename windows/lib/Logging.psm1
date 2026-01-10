#
# Logging.psm1 - Logging utilities
#
# Usage:
#   Import-Module .\Logging.psm1
#   Initialize-Logging -ScriptName "update-system"
#   Write-LogInfo "Starting process"
#
# Dependencies:
#   - Colors.psm1 (must be imported first by calling script)
#

# Default log directory (can be overridden)
$Script:LogDir = Join-Path $env:LOCALAPPDATA 'system-lifecycle\logs'
$Script:LogFile = $null
$Script:Quiet = $false

<#
.SYNOPSIS
    Initializes logging for a script.

.DESCRIPTION
    Creates the log directory if needed and sets up a timestamped log file.
    All subsequent logging calls will write to this file.

.PARAMETER ScriptName
    The script name prefix for the log file (e.g., "Update-System").

.PARAMETER LogDirectory
    Optional. Override the default log directory.

.PARAMETER Quiet
    If specified, suppresses console output (still logs to file).

.EXAMPLE
    Initialize-Logging -ScriptName "Update-System"

.EXAMPLE
    Initialize-Logging -ScriptName "Update-System" -Quiet
#>
function Initialize-Logging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptName,

        [Parameter()]
        [string]$LogDirectory,

        [Parameter()]
        [switch]$Quiet
    )

    if ($LogDirectory) {
        $Script:LogDir = $LogDirectory
    }

    $Script:Quiet = $Quiet

    # Create log directory if it doesn't exist
    if (-not (Test-Path $Script:LogDir)) {
        New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null
    }

    # Create timestamped log file
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $Script:LogFile = Join-Path $Script:LogDir "${ScriptName}-${timestamp}.log"

    # Create the log file
    New-Item -ItemType File -Path $Script:LogFile -Force | Out-Null

    Write-LogInfo "Log file: $Script:LogFile"
}

<#
.SYNOPSIS
    Core logging function.

.DESCRIPTION
    Writes a message to both the log file (if initialized) and the console
    (unless quiet mode is enabled).

.PARAMETER Level
    The log level: INFO, SUCCESS, WARNING, or ERROR.

.PARAMETER Message
    The message to log.

.EXAMPLE
    Write-LogMessage -Level INFO -Message "Starting update"
#>
function Write-LogMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"

    # Always write to log file if initialized
    if ($Script:LogFile) {
        Add-Content -Path $Script:LogFile -Value $logEntry -Encoding UTF8
    }

    # Write to console unless quiet mode
    if (-not $Script:Quiet) {
        $color = switch ($Level) {
            'INFO'    { 'Blue' }
            'SUCCESS' { 'Green' }
            'WARNING' { 'Yellow' }
            'ERROR'   { 'Red' }
        }

        Write-ColorOutput -Message "[$Level] $Message" -Color $color
    }
}

<#
.SYNOPSIS
    Logs an informational message.

.PARAMETER Message
    The message to log.

.EXAMPLE
    Write-LogInfo "Processing started"
#>
function Write-LogInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Message
    )

    process {
        Write-LogMessage -Level 'INFO' -Message $Message
    }
}

<#
.SYNOPSIS
    Logs a success message.

.PARAMETER Message
    The message to log.

.EXAMPLE
    Write-LogSuccess "Update completed"
#>
function Write-LogSuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Message
    )

    process {
        Write-LogMessage -Level 'SUCCESS' -Message $Message
    }
}

<#
.SYNOPSIS
    Logs a warning message.

.PARAMETER Message
    The message to log.

.EXAMPLE
    Write-LogWarning "Package not found, skipping"
#>
function Write-LogWarning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Message
    )

    process {
        Write-LogMessage -Level 'WARNING' -Message $Message
    }
}

<#
.SYNOPSIS
    Logs an error message.

.PARAMETER Message
    The message to log.

.EXAMPLE
    Write-LogError "Update failed"
#>
function Write-LogError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Message
    )

    process {
        Write-LogMessage -Level 'ERROR' -Message $Message
    }
}

<#
.SYNOPSIS
    Displays a section header.

.DESCRIPTION
    Writes a formatted section header to both console and log file.

.PARAMETER Title
    The section title to display.

.EXAMPLE
    Write-Section "Windows Update"
#>
function Write-Section {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title
    )

    if (-not $Script:Quiet) {
        $line = [string]::new([char]0x2501, 50)  # Unicode box drawing character
        Write-ColorOutput -Message "`n$line" -Color 'Blue'
        Write-ColorOutput -Message "  $Title" -Color 'Blue'
        Write-ColorOutput -Message "$line" -Color 'Blue'
    }

    Write-LogInfo "=== $Title ==="
}

<#
.SYNOPSIS
    Gets the current log file path.

.DESCRIPTION
    Returns the path to the current log file, or $null if logging is not initialized.

.EXAMPLE
    $logPath = Get-LogFilePath
#>
function Get-LogFilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return $Script:LogFile
}

<#
.SYNOPSIS
    Sets quiet mode for logging.

.DESCRIPTION
    When quiet mode is enabled, console output is suppressed but file logging continues.

.PARAMETER Enabled
    Set to $true to enable quiet mode, $false to disable.

.EXAMPLE
    Set-QuietMode -Enabled $true
#>
function Set-QuietMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$Enabled
    )

    $Script:Quiet = $Enabled
}

<#
.SYNOPSIS
    Tests if a line should be logged or filtered out.

.DESCRIPTION
    Filters out noise from external command output including progress indicators,
    spinner characters, and download percentage updates.

.PARAMETER Line
    The line of output to test.

.OUTPUTS
    [bool] True if the line should be logged, false if it should be filtered.

.EXAMPLE
    if (Test-ShouldLogLine $line) { Write-LogInfo $line }
#>
function Test-ShouldLogLine {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string]$Line
    )

    process {
        # Skip empty/whitespace-only lines
        if ($Line -notmatch '\S') { return $false }

        # Skip download progress lines (Chocolatey pattern)
        if ($Line -match 'Progress: Downloading.*\d+%') { return $false }

        # Skip spinner/progress characters (single char lines like -, \, |, /)
        if ($Line -match '^\s*[-\\|/]\s*$') { return $false }

        # Skip progress bar lines (garbled Unicode block elements + percentage)
        # Pattern: lines ending with percentage or size that contain garbled Γû sequences
        if ($Line -match 'Γû[êÆ].*\d+%\s*$') { return $false }
        if ($Line -match 'Γû[êÆ].*\d+(\.\d+)?\s*(KB|MB|GB)\s*/') { return $false }

        # Skip ANSI escape sequence only lines
        if ($Line -match '^\s*(\x1b\[[0-9;]*m)*\s*$') { return $false }

        # Skip "is the latest version available" messages (Chocolatey)
        if ($Line -match 'is the latest version available based on your source') { return $false }

        return $true
    }
}

Export-ModuleMember -Function Initialize-Logging, Write-LogMessage,
    Write-LogInfo, Write-LogSuccess, Write-LogWarning, Write-LogError,
    Write-Section, Get-LogFilePath, Set-QuietMode, Test-ShouldLogLine
