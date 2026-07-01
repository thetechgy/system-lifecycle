#
# VersionCheck.psm1 - Check if local scripts are up to date
#
# Usage:
#   Import-Module .\VersionCheck.psm1
#   Test-ForUpdates
#
# Description:
#   Compares local HEAD against the locally cached origin/main ref and warns if
#   behind. Fetching from the remote is opt-in.
#
# Dependencies:
#   - Colors.psm1 (must be imported first by calling script)
#

<#
.SYNOPSIS
    Gets the repository root directory.

.DESCRIPTION
    Determines the repository root based on the location of this module.
    Assumes the structure: repo/windows/lib/VersionCheck.psm1
#>
function Get-RepoRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # This module is in windows/lib/, so repo root is two levels up
    # $PSScriptRoot is the directory containing this module file
    $windowsDir = Split-Path -Parent $PSScriptRoot
    $repoRoot = Split-Path -Parent $windowsDir
    return (Resolve-Path $repoRoot).Path
}

<#
.SYNOPSIS
    Checks for updates from origin/main.

.DESCRIPTION
    Compares the local HEAD against the locally cached origin/main ref and warns
    if the local repository is behind. Gracefully handles cases where git is not
    available, the directory is not a repository, or the remote ref is missing.

.PARAMETER Fetch
    Fetch origin/main before comparing revisions. This is opt-in because the
    default version check must be side-effect free.

.EXAMPLE
    Test-ForUpdates
#>
function Test-ForUpdates {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Fetch
    )

    $repoRoot = Get-RepoRoot

    # Skip if git is not installed
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host 'Version check: skipped (git not installed)'
        return
    }

    # Skip if not a git repository
    $gitDir = Join-Path $repoRoot '.git'
    if (-not (Test-Path $gitDir)) {
        Write-Host 'Version check: skipped (not a git repository)'
        return
    }

    if ($Fetch) {
        try {
            $env:GIT_TERMINAL_PROMPT = '0'
            $null = & git -C $repoRoot fetch origin main --quiet
            if ($LASTEXITCODE -ne 0) {
                Write-Host 'Version check: skipped (unable to reach remote)'
                return
            }
        } catch {
            Write-Host 'Version check: skipped (unable to reach remote)'
            return
        } finally {
            Remove-Item Env:\GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue
        }
    }

    # Get local and remote revisions
    try {
        $localRev = git -C $repoRoot rev-parse HEAD 2>$null
        $remoteRev = git -C $repoRoot rev-parse origin/main 2>$null
    } catch {
        return
    }

    if (-not $localRev -or -not $remoteRev) {
        Write-Host 'Version check: skipped (origin/main ref not available)'
        return
    }

    # If already up to date, report success
    if ($localRev -eq $remoteRev) {
        Write-ColorOutput -Message 'Version check: up to date' -Color 'Green'
        return
    }

    # Count how many commits behind
    try {
        $behindCount = git -C $repoRoot rev-list --count HEAD..origin/main 2>$null
        $behindCount = [int]$behindCount
    } catch {
        return
    }

    # Only warn if actually behind (not ahead or diverged)
    if ($behindCount -gt 0) {
        Write-ColorOutput -Message "Version check: $behindCount commit(s) behind origin/main" -Color 'Yellow'
        Write-Host '    Run: git pull'
        Write-Host ''
    } else {
        Write-Host 'Version check: local changes ahead of or diverged from origin/main'
    }
}

Export-ModuleMember -Function Test-ForUpdates, Get-RepoRoot
