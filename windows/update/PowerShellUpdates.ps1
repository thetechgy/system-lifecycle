# Internal stable PowerShell update helpers; Windows PowerShell 5.1 and 7.
function Invoke-WingetCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Arguments)
    # Native failures are classified below, including with PS 7's opt-in native errors.
    $PSNativeCommandUseErrorActionPreference = $false
    $output = @(& winget @Arguments 2>&1)
    $code = '{0:X8}' -f ([long]$LASTEXITCODE -band 0xffffffffL)
    return [pscustomobject]@{ Code = $code; Output = $output }
}

function Get-WingetInventory {
    [CmdletBinding()]
    param()
    $path = [IO.Path]::GetTempFileName()
    try {
        $result = Invoke-WingetCommand @('export', '--output', $path, '--include-versions', '--disable-interactivity', '--accept-source-agreements')
        if ($result.Code -eq '8A150014') { return }
        if ($result.Code -ne '00000000') { throw 'WinGet inventory failed.' }
        $inventory = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop
        if (-not $inventory.PSObject.Properties['Sources']) { throw 'Invalid WinGet inventory.' }
        foreach ($source in @($inventory.Sources)) {
            $name = $source.SourceDetails.Name
            if ([string]::IsNullOrWhiteSpace($name) -or $name.StartsWith('-') -or -not $source.PSObject.Properties['Packages']) { throw 'Invalid WinGet source inventory.' }
            foreach ($package in @($source.Packages)) {
                if ($package.PackageIdentifier -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$') { throw 'Invalid WinGet package identity.' }
            }
        }
        # Validate the entire inventory before emitting any work.
        foreach ($source in @($inventory.Sources)) {
            foreach ($package in @($source.Packages)) {
                [pscustomobject]@{ Id = $package.PackageIdentifier; Source = $source.SourceDetails.Name }
            }
        }
    } finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
}

function Test-PowerShellUpdateInUse {
    [CmdletBinding()]
    param()
    try {
        return @((Get-CimInstance -ClassName Win32_Process -Filter "Name='pwsh.exe'" -ErrorAction Stop)).Count -gt 0
    } catch {
        Write-LogWarning 'Cannot inspect PowerShell processes; deferring application installers'
        return $true
    }
}

function Update-PowerShellPackage {
    [CmdletBinding()]
    param([ValidateSet('machine', 'user')][string]$Scope, [switch]$DryRun)
    Write-Section 'Stable PowerShell 7'
    if ($DryRun) {
        Write-LogInfo "[DRY-RUN] Would check installed $Scope PowerShell 7 and upgrade stable Microsoft.PowerShell when no PowerShell 7 sessions are open"
        return
    }
    if (-not (Test-CommandExists 'winget')) {
        Write-LogWarning 'WinGet unavailable; skipping PowerShell update (manual update required)'
        return
    }
    $query = @('--id', 'Microsoft.PowerShell', '--exact', '--source', 'winget', '--scope', $Scope,
        '--disable-interactivity', '--accept-source-agreements')
    $installed = Invoke-WingetCommand (@('list') + $query)
    if ($installed.Code -eq '8A150014') { Write-LogInfo "No WinGet-recognized $Scope stable PowerShell installation; skipping"; return }
    if ($installed.Code -ne '00000000') { throw 'PowerShell installation discovery failed.' }
    $available = Invoke-WingetCommand (@('list', '--upgrade-available') + $query)
    if ($available.Code -eq '8A150014') { Write-LogInfo 'No applicable unpinned PowerShell upgrade available'; return }
    if ($available.Code -ne '00000000') { throw 'PowerShell update discovery failed.' }
    if (Test-PowerShellUpdateInUse) {
        Write-LogWarning 'PowerShell update deferred: close PowerShell 7 sessions and retry from Windows PowerShell 5.1'
        if ($Script:ExitCode -eq 0) { $Script:ExitCode = 1 }
        return
    }
    # Recheck immediately before installation. This is a preflight, not a process lock.
    if (Test-PowerShellUpdateInUse) { throw 'PowerShell update deferred because a session opened.' }
    $result = Invoke-WingetCommand (@('upgrade', '--all', '--silent', '--accept-package-agreements') + $query)
    if ($result.Code -eq '8A15002B') { Write-LogInfo 'No applicable PowerShell upgrade available'; return }
    if ($result.Code -eq '8A150109') { Write-LogWarning 'PowerShell update requires a reboot to finish'; return }
    if ($result.Code -ne '00000000') { throw "PowerShell upgrade failed (status $($result.Code))." }
    Write-LogSuccess 'Stable PowerShell package updated; open a new session to use it'
}
