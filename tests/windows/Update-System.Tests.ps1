BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:UpdateScript = Join-Path $script:RepoRoot 'windows/update/Update-System.ps1'

    . $script:UpdateScript
}

Describe 'Windows module imports' {
    It 'imports shared modules cleanly' {
        $modulePaths = @(
            'windows/lib/Colors.psm1'
            'windows/lib/Logging.psm1'
            'windows/lib/Utils.psm1'
            'windows/lib/VersionCheck.psm1'
        )

        foreach ($modulePath in $modulePaths) {
            { Import-Module (Join-Path $script:RepoRoot $modulePath) -Force -ErrorAction Stop } | Should -Not -Throw
        }
    }
}

Describe 'Update-System ShouldProcess behavior' {
    BeforeEach {
        $script:CalledPhases = @()

        Mock Test-ForUpdates {}
        Mock Test-Administrator { return $true }
        Mock Initialize-Logging {}
        Mock Write-LogInfo {}
        Mock Write-LogSuccess {}
        Mock Write-LogError {}
        Mock Write-LogWarning {}
        Mock Write-Section {}
        Mock Get-SystemInfo {}
        Mock Test-RebootRequired { return $false }
        Mock Get-LogFilePath { return $null }

        Mock Update-WindowsSystem { $script:CalledPhases += 'Windows' }
        Mock Update-VendorFirmware { $script:CalledPhases += 'Vendor' }
        Mock Update-WingetPackages { $script:CalledPhases += 'Winget' }
        Mock Update-ChocolateyPackages { $script:CalledPhases += 'Chocolatey' }
        Mock Update-ScoopPackages { $script:CalledPhases += 'Scoop' }
        Mock Update-NpmPackages { $script:CalledPhases += 'Npm' }
        Mock Update-PatchMyPC { $script:CalledPhases += 'PatchMyPC' }
        Mock Invoke-Cleanup { $script:CalledPhases += 'Cleanup' }
    }

    It 'does not run state-changing update phases under WhatIf' {
        Main -WhatIf | Should -Be 0

        $script:CalledPhases | Should -BeNullOrEmpty
    }

    It 'keeps DryRun as the richer preview path' {
        Main -DryRun | Should -Be 0

        $script:CalledPhases | Should -Contain 'Windows'
        $script:CalledPhases | Should -Contain 'Winget'
        $script:CalledPhases | Should -Contain 'Cleanup'
    }

    It 'does not route skipped package managers through top-level phase guards' {
        Main -DryRun -NoChocolatey -NoScoop -NoNpm -NoPatchMyPC | Should -Be 0

        $script:CalledPhases | Should -Contain 'Windows'
        $script:CalledPhases | Should -Contain 'Winget'
        $script:CalledPhases | Should -Contain 'Cleanup'
        $script:CalledPhases | Should -Not -Contain 'Chocolatey'
        $script:CalledPhases | Should -Not -Contain 'Scoop'
        $script:CalledPhases | Should -Not -Contain 'Npm'
        $script:CalledPhases | Should -Not -Contain 'PatchMyPC'
    }

    It 'does not emit WhatIf messages for skipped package managers' {
        $whatIfOutput = Main -WhatIf -NoChocolatey -NoScoop -NoNpm -NoPatchMyPC 6>&1 | Out-String

        $whatIfOutput | Should -Not -Match 'Chocolatey packages'
        $whatIfOutput | Should -Not -Match 'Scoop packages'
        $whatIfOutput | Should -Not -Match 'npm global packages'
        $whatIfOutput | Should -Not -Match 'PatchMyPC applications'
    }
}
