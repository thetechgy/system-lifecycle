BeforeAll {
    . (Join-Path $PSScriptRoot '../../windows/update/Update-System.ps1')
    $script:AddedPowerShellCimStub = -not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)
    if ($script:AddedPowerShellCimStub) {
        function global:Get-CimInstance { param($ClassName, $Filter) throw 'Windows only' }
    }
}

Describe 'Stable PowerShell update boundary' {
    BeforeEach {
        $Script:ExitCode = 0
        Mock Write-Section {}
        Mock Write-LogInfo {}
        Mock Write-LogWarning {}
        Mock Write-LogSuccess {}
        Mock Test-CommandExists { $true }
        Mock Test-PowerShellUpdateInUse { $false }
        Mock Invoke-WingetCommand { [pscustomobject]@{ Code = '00000000'; Output = @() } }
    }
    It 'targets only stable PowerShell in the requested scope with pin-preserving bulk semantics' {
        Update-PowerShellPackage -Scope machine
        Should -Invoke Invoke-WingetCommand -Times 1 -ParameterFilter {
            $Arguments[0] -eq 'upgrade' -and $Arguments -contains '--all' -and
            $Arguments -contains 'Microsoft.PowerShell' -and $Arguments -contains 'winget' -and
            $Arguments -contains '--exact' -and $Arguments -contains 'machine' -and
            $Arguments -notcontains '--force' -and $Arguments -notcontains '--allow-reboot'
        }
    }
    It 'routes user installations explicitly' {
        Update-PowerShellPackage -Scope user
        Should -Invoke Invoke-WingetCommand -Times 3 -ParameterFilter { $Arguments -contains 'user' }
    }
    It 'skips absent installations without installing them' {
        Mock Invoke-WingetCommand { @{ Code = '8A150014' } }
        Update-PowerShellPackage -Scope machine
        Should -Invoke Invoke-WingetCommand -Times 1
    }
    It 'does not defer when no applicable upgrade is available' {
        Mock Invoke-WingetCommand { @{ Code = '8A150014' } } -ParameterFilter { $Arguments -contains '--upgrade-available' }
        Update-PowerShellPackage -Scope machine
        $Script:ExitCode | Should -Be 0
        Should -Invoke Test-PowerShellUpdateInUse -Times 0
    }
    It 'defers available updates without invoking the installer when sessions are open' {
        Mock Test-PowerShellUpdateInUse { $true }
        Update-PowerShellPackage -Scope machine
        $Script:ExitCode | Should -Be 1
        Should -Invoke Invoke-WingetCommand -Times 0 -ParameterFilter { $Arguments[0] -eq 'upgrade' }
    }
    It 'fails discovery errors rather than treating them as missing installs' {
        Mock Invoke-WingetCommand { @{ Code = '8A150045' } }
        { Update-PowerShellPackage -Scope machine } | Should -Throw '*discovery failed*'
    }
    It 'retains native installer failure' {
        Mock Invoke-WingetCommand { @{ Code = '80004005' } } -ParameterFilter { $Arguments[0] -eq 'upgrade' }
        { Update-PowerShellPackage -Scope machine } | Should -Throw '*80004005*'
    }
    It 'does not discover, scan processes, or install during DryRun' {
        Update-PowerShellPackage -Scope machine -DryRun
        Should -Invoke Invoke-WingetCommand -Times 0
        Should -Invoke Test-PowerShellUpdateInUse -Times 0
    }
    It 'excludes stable PowerShell while continuing other WinGet packages and failures' {
        Mock Get-WingetInventory { @(@{ Id='Microsoft.PowerShell'; Source='winget' }, @{ Id='Vendor.App'; Source='winget' }, @{ Id='Other.App'; Source='winget' }) }
        Mock Invoke-WingetCommand { @{ Code='80004005' } } -ParameterFilter { $Arguments -contains 'Vendor.App' }
        Update-WingetPackages
        Should -Invoke Invoke-WingetCommand -Times 0 -ParameterFilter { $Arguments -contains 'Microsoft.PowerShell' }
        Should -Invoke Invoke-WingetCommand -Times 1 -ParameterFilter { $Arguments -contains 'Other.App' -and $Arguments -contains '--all' }
        $Script:ExitCode | Should -Be 4
    }
}

Describe 'WinGet structured inventory' {
    BeforeEach {
        Mock Invoke-WingetCommand {
            $path = $Arguments[[array]::IndexOf($Arguments, '--output') + 1]
            '{"Sources":[{"SourceDetails":{"Name":"winget"},"Packages":[{"PackageIdentifier":"Microsoft.PowerShell"},{"PackageIdentifier":"Vendor.App"}]}]}' | Set-Content -LiteralPath $path
            @{ Code = '00000000' }
        }
    }
    It 'reads identities without parsing display output' {
        $packages = @(Get-WingetInventory)
        $packages.Count | Should -Be 2
        $packages[1].Id | Should -Be 'Vendor.App'
    }
    It 'rejects malformed inventory before emitting any work' {
        Mock Invoke-WingetCommand {
            $path = $Arguments[[array]::IndexOf($Arguments, '--output') + 1]
            '{"Sources":[{"SourceDetails":{"Name":"winget"},"Packages":[{"PackageIdentifier":"Vendor.App"},{"PackageIdentifier":"--all"}]}]}' | Set-Content -LiteralPath $path
            @{ Code = '00000000' }
        }
        { Get-WingetInventory } | Should -Throw '*Invalid WinGet package*'
    }
}

Describe 'PowerShell process inspection' {
    BeforeEach { Mock Write-LogWarning {} }
    It 'fails closed when process inspection is unavailable' {
        Mock Get-CimInstance { throw 'access denied' }
        Test-PowerShellUpdateInUse | Should -BeTrue
    }
    It 'detects an open PowerShell 7 process' {
        Mock Get-CimInstance { @{ ProcessId = 123 } }
        Test-PowerShellUpdateInUse | Should -BeTrue
    }
    It 'allows updating without PowerShell 7 processes' {
        Mock Get-CimInstance { @() }
        Test-PowerShellUpdateInUse | Should -BeFalse
    }
}

Describe 'Other installer deferral' {
    BeforeEach {
        $Script:ExitCode = 0
        Mock Test-CommandExists { $true }
        Mock Test-PowerShellUpdateInUse { $true }
        Mock Find-PatchMyPC { 'fixture-patchmypc.exe' }
        Mock Write-LogInfo {}
        Mock Write-LogWarning {}
        Mock Write-Section {}
    }
    It 'defers Chocolatey while PowerShell is running' {
        Update-ChocolateyPackages
        $Script:ExitCode | Should -Be 1
    }
    It 'defers Scoop while PowerShell is running' {
        Update-ScoopPackages
        $Script:ExitCode | Should -Be 1
    }
    It 'defers PatchMyPC while PowerShell is running' {
        Update-PatchMyPC
        $Script:ExitCode | Should -Be 1
    }
}

AfterAll {
    if ($script:AddedPowerShellCimStub) { Remove-Item Function:\Get-CimInstance -ErrorAction SilentlyContinue }
}
