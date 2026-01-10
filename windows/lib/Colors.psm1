#
# Colors.psm1 - Terminal color definitions
#
# Usage:
#   Import-Module .\Colors.psm1
#   Write-ColorOutput -Message "Success" -Color Green
#

# Detect if running in a terminal that supports ANSI colors
$Script:SupportsAnsi = $false
if ($Host.UI.SupportsVirtualTerminal) {
    $Script:SupportsAnsi = $true
} elseif ($env:TERM -match 'xterm|color|ansi') {
    $Script:SupportsAnsi = $true
} elseif ($env:ConEmuANSI -eq 'ON') {
    $Script:SupportsAnsi = $true
} elseif ($env:WT_SESSION) {
    # Windows Terminal
    $Script:SupportsAnsi = $true
}

# ANSI color codes (used when supported)
$Script:AnsiColors = @{
    Red     = "`e[31m"
    Green   = "`e[32m"
    Yellow  = "`e[33m"
    Blue    = "`e[34m"
    Magenta = "`e[35m"
    Cyan    = "`e[36m"
    White   = "`e[37m"
    Bold    = "`e[1m"
    Reset   = "`e[0m"
}

# Console color mapping (fallback for non-ANSI terminals)
$Script:ConsoleColors = @{
    Red     = 'Red'
    Green   = 'Green'
    Yellow  = 'Yellow'
    Blue    = 'Blue'
    Magenta = 'Magenta'
    Cyan    = 'Cyan'
    White   = 'White'
}

<#
.SYNOPSIS
    Writes colored output to the console.

.DESCRIPTION
    Writes a message to the console with the specified color. Uses ANSI escape
    codes when supported, otherwise falls back to Write-Host -ForegroundColor.

.PARAMETER Message
    The message to write to the console.

.PARAMETER Color
    The color to use. Valid values: Red, Green, Yellow, Blue, Magenta, Cyan, White.

.PARAMETER NoNewline
    If specified, does not append a newline after the message.

.EXAMPLE
    Write-ColorOutput -Message "Success!" -Color Green

.EXAMPLE
    Write-ColorOutput -Message "Warning: " -Color Yellow -NoNewline
#>
function Write-ColorOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White')]
        [string]$Color = 'White',

        [Parameter()]
        [switch]$NoNewline
    )

    process {
        if ($Script:SupportsAnsi) {
            $colorCode = $Script:AnsiColors[$Color]
            $reset = $Script:AnsiColors['Reset']
            if ($NoNewline) {
                Write-Host "${colorCode}${Message}${reset}" -NoNewline
            } else {
                Write-Host "${colorCode}${Message}${reset}"
            }
        } else {
            $consoleColor = $Script:ConsoleColors[$Color]
            Write-Host $Message -ForegroundColor $consoleColor -NoNewline:$NoNewline
        }
    }
}

<#
.SYNOPSIS
    Tests if the current terminal supports ANSI colors.

.DESCRIPTION
    Returns $true if the terminal supports ANSI escape codes, $false otherwise.

.EXAMPLE
    if (Test-AnsiSupport) { Write-Host "Colors supported!" }
#>
function Test-AnsiSupport {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    return $Script:SupportsAnsi
}

Export-ModuleMember -Function Write-ColorOutput, Test-AnsiSupport
