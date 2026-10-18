BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:UpdateScript = Join-Path $script:RepoRoot 'windows/update/Update-System.ps1'

    . $script:UpdateScript
    $script:AddedCimStub = -not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)
    $script:AddedSignatureStub = -not (Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue)
    if ($script:AddedCimStub) { function global:Get-CimInstance { param($ClassName) throw 'Windows acceptance only' } }
    if ($script:AddedSignatureStub) { function global:Get-AuthenticodeSignature { param($LiteralPath) throw 'Windows acceptance only' } }
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
        Mock Update-NpmPackages { param($Skip, $NoCodex)
            if (-not $Skip) { $script:CalledPhases += 'Npm' }
            if (-not $NoCodex) { $script:CalledPhases += 'NpmCodex' }
        }
        Mock Update-NvmRuntime { $script:CalledPhases += 'Nvm' }
        Mock Update-StandaloneCodex { $script:CalledPhases += 'Codex' }
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

Describe 'Unelevated update orchestration' {
    BeforeEach {
        Mock Test-ForUpdates {}
        Mock Initialize-Logging {}
        Mock Write-LogInfo {}
        Mock Write-LogError {}
        Mock Write-LogWarning {}
        Mock Test-Administrator { $false }
        Mock Start-SystemUpdateChild { 0 }
        Mock Invoke-SystemUpdate { 0 }
        Mock Update-NvmRuntime { @{ Node = 'fixture-node'; Cli = 'fixture-cli' } }
        Mock Update-NpmPackages {}
        Mock Update-StandaloneCodex {}
    }

    It 'waits for elevated system work then updates tools in the caller' {
        Main | Should -Be 0
        Should -Invoke Start-SystemUpdateChild -Times 1 -Exactly
        Should -Invoke Update-NvmRuntime -Times 1 -Exactly
        Should -Invoke Update-NpmPackages -Times 1 -Exactly -ParameterFilter { $Runtime.Node -eq 'fixture-node' }
    }

    It 'rejects a full elevated invocation before any update' {
        Mock Test-Administrator { $true }
        Main | Should -Be 3
        Should -Invoke Start-SystemUpdateChild -Times 0
        Should -Invoke Update-NvmRuntime -Times 0
        Should -Invoke Invoke-SystemUpdate -Times 0
    }

    It 'allows elevated SystemOnly without developer work' {
        Mock Test-Administrator { $true }
        Main -SystemOnly | Should -Be 0
        Should -Invoke Invoke-SystemUpdate -Times 1
        Should -Invoke Update-NvmRuntime -Times 0
        Should -Invoke Update-NpmPackages -Times 0
    }

    It 'rejects unelevated SystemOnly' {
        Main -SystemOnly | Should -Be 3
        Should -Invoke Invoke-SystemUpdate -Times 0
    }

    It 'retains child failure while independent tool updates continue' {
        Mock Start-SystemUpdateChild { 5 }
        Main | Should -Be 5
        Should -Invoke Update-NpmPackages -Times 1
    }

    It 'retains UAC cancellation while user tools still run' {
        Mock Start-SystemUpdateChild { throw 'cancelled' }
        Main | Should -Be 1
        Should -Invoke Update-NpmPackages -Times 1
    }

    It 'stops dependent npm work after failed runtime verification and retains standalone results' {
        Mock Update-NvmRuntime { throw 'verification failed' }
        Main | Should -Be 6
        Should -Invoke Update-NpmPackages -Times 0
        Should -Invoke Update-StandaloneCodex -Times 1
    }

    It 'retains a child failure when the developer phase also fails' {
        Mock Start-SystemUpdateChild { 5 }
        Mock Update-NvmRuntime { throw 'failed' }
        Main | Should -Be 5
    }

    It 'keeps Codex independently enabled when NoNpm is set' {
        Main -NoNpm | Should -Be 0
        Should -Invoke Update-NpmPackages -Times 1 -ParameterFilter { $Skip -and -not $NoCodex }
    }

    It 'honors all developer skip switches' {
        Main -NoNvm -NoNpm -NoCodex | Should -Be 0
        Should -Invoke Update-NvmRuntime -Times 0
        Should -Invoke Update-NpmPackages -Times 0
        Should -Invoke Update-StandaloneCodex -Times 0
    }

    It 'does not elevate or change developer tools under WhatIf' {
        Main -WhatIf | Should -Be 0
        Should -Invoke Start-SystemUpdateChild -Times 0
        Should -Invoke Update-NvmRuntime -Times 0
        Should -Invoke Update-NpmPackages -Times 0
        Should -Invoke Update-StandaloneCodex -Times 0
        Should -Invoke Test-Administrator -Times 0
    }

    It 'passes preview flags to phases without elevation' {
        Main -DryRun | Should -Be 0
        Should -Invoke Start-SystemUpdateChild -Times 0
        Should -Invoke Update-NvmRuntime -Times 1 -ParameterFilter { $DryRun }
        Should -Invoke Update-NpmPackages -Times 1 -ParameterFilter { $DryRun }
        Should -Invoke Update-StandaloneCodex -Times 1 -ParameterFilter { $DryRun }
    }
}

Describe 'Elevated child command construction' {
    BeforeEach {
        Mock Get-Process { @{ Path = 'fixture-powershell.exe' } }
        Mock Start-Process { @{ ExitCode = 9 } }
    }

    It 'uses the current executable and safely forwards only supported system switches' {
        Start-SystemUpdateChild -Options @{ Quiet = $true; IncludeDrivers = $true; Clean = $true; NoNpm = $true; NoCodex = $true; Unexpected = 'injected' } | Should -Be 9
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[-1]))
            $FilePath -eq 'fixture-powershell.exe' -and $Verb -eq 'RunAs' -and $Wait -and $PassThru -and
            $decoded -match '-SystemOnly -Quiet -IncludeDrivers -Clean$' -and
            $decoded -notmatch 'NoNpm|NoCodex|injected|ExecutionPolicy'
        }
    }

    It 'quotes paths with apostrophes and spaces as one literal script path' {
        $old = $Script:ScriptDir
        try {
            $Script:ScriptDir = "/fixture user's/update directory"
            $null = Start-SystemUpdateChild -Options @{}
            Should -Invoke Start-Process -Times 1 -ParameterFilter {
                $decoded = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($ArgumentList[-1]))
                $decoded -match "fixture user''s/update directory" -and $decoded.StartsWith("& '")
            }
        } finally { $Script:ScriptDir = $old }
    }
}

Describe 'Nvm migration boundary' {
    AfterAll { $env:LOCALAPPDATA = $script:PreviousLocalAppData }
    BeforeAll {
        $script:PreviousLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $TestDrive
    }
    BeforeEach {
        Mock Write-LogInfo {}
        Mock Write-LogWarning {}
        Mock Assert-NvmProcessesStopped {}
        Mock Save-NvmRecovery {}
        Mock Install-NvmRelease {}
        Mock Update-ProcessEnvironment {}
        Mock Get-Command { @{ Source = 'fixture-nvm.exe' } } -ParameterFilter { $Name -eq 'nvm.exe' }
        Mock Get-NvmState {
            @{ Version = '1.2.2'; Major = 1; Root = '/fixture/runtimes'; ProgramRoot = '/fixture/program'; LinkRoot = '/fixture/link'; Active = '20.0.0'; Runtimes = @{
                '20.0.0' = @{ Node = 'old-node'; Cli = 'old-cli'; Hash = 'old-hash'; Packages = @{ tool = @{ version = '1.0.0'; link = $null } } }
            } }
        }
        Mock Invoke-DeveloperCommand { '' }
        Mock Invoke-RestMethod { @(@{ version = 'v24.0.0'; lts = 'Fixture' }) }
        Mock Invoke-NpmWorker { @{} }
    }

    It 'does not download, inventory, switch runtimes or scan processes in DryRun' {
        Update-NvmRuntime -DryRun | Should -BeNullOrEmpty
        Should -Invoke Install-NvmRelease -Times 0
        Should -Invoke Get-NvmState -Times 0
        Should -Invoke Assert-NvmProcessesStopped -Times 0
        Should -Invoke Invoke-DeveloperCommand -Times 0
    }

    It 'defers migration when an affected process is running' {
        Mock Assert-NvmProcessesStopped { throw 'running process' }
        { Update-NvmRuntime } | Should -Throw '*running process*'
        Should -Invoke Install-NvmRelease -Times 0
        Should -Invoke Save-NvmRecovery -Times 0
    }

    It 'saves recovery before attempting legacy migration and rejects unverified migration' {
        { Update-NvmRuntime } | Should -Throw '*migration was not verified*'
        Should -Invoke Save-NvmRecovery -Times 1
        Should -Invoke Install-NvmRelease -Times 1
        Should -Invoke Invoke-DeveloperCommand -Times 0
    }

    It 'rejects missing or changed retained runtimes' {
        $before = @{ Runtimes = @{ '20.0.0' = @{ Hash = 'original' } } }
        { Assert-NvmPreserved $before @{ Runtimes = @{} } } | Should -Throw '*not preserved*'
        { Assert-NvmPreserved $before @{ Runtimes = @{ '20.0.0' = @{ Hash = 'changed' } } } } | Should -Throw '*not preserved*'
        Should -Invoke Invoke-NpmWorker -Times 0
    }

    It 'verifies retained package versions and links through the shared worker' {
        $packages = @{ 'local-tool' = @{ version = '1.0.0'; link = '/fixture/project' } }
        $before = @{ Runtimes = @{ '20.0.0' = @{ Hash = 'same'; Packages = $packages } } }
        $after = @{ Runtimes = @{ '20.0.0' = @{ Hash = 'same'; Node = 'new-location-node'; Cli = 'new-location-cli' } } }
        Assert-NvmPreserved $before $after
        Should -Invoke Invoke-NpmWorker -Times 1 -ParameterFilter { $Action -eq 'verify' -and $Packages.'local-tool'.link -eq '/fixture/project' -and $Node -eq 'new-location-node' }
    }

    It 'propagates failed package preservation' {
        Mock Invoke-NpmWorker { throw 'linked package missing' }
        $state = @{ Runtimes = @{ '20.0.0' = @{ Hash = 'same'; Packages = @{}; Node = 'node'; Cli = 'cli' } } }
        { Assert-NvmPreserved $state $state } | Should -Throw '*linked package missing*'
    }
}

Describe 'Process and Codex source detection' {
    BeforeAll {
        $script:PreviousUserProfile = $env:USERPROFILE
        $env:USERPROFILE = $TestDrive
    }
    AfterAll { $env:USERPROFILE = $script:PreviousUserProfile }
    BeforeEach {
        Mock Write-LogInfo {}
        Mock Write-LogWarning {}
        Mock Invoke-DeveloperCommand { 'update    Update installed release' }
        Mock Test-Path { $true }
        Mock Get-CimInstance { @() }
        Mock Get-StandaloneCodexRoot { $null }
        Mock Get-Content { 'node_modules/@openai/codex/bin/codex.js' }
    }

    It 'detects affected process paths case-insensitively with a directory boundary' {
        Mock Get-CimInstance { @(@{ Name = 'node.exe'; ExecutablePath = '/fixture/nvm/node.exe' }) }
        { Assert-NvmProcessesStopped @('/fixture/nvm') } | Should -Throw '*migration deferred*'
    }

    It 'does not confuse a sibling directory with an affected root' {
        Mock Get-CimInstance { @(@{ Name = 'node.exe'; ExecutablePath = '/fixture/nvm-other/node.exe' }) }
        { Assert-NvmProcessesStopped @('/fixture/nvm') } | Should -Not -Throw
    }

    It 'fails closed when an affected process cannot be inspected' {
        Mock Get-CimInstance { @(@{ Name = 'node.exe'; ExecutablePath = $null }) }
        { Assert-NvmProcessesStopped @('/fixture/nvm') } | Should -Throw '*Cannot inspect*'
    }

    It 'does not invoke standalone updates for npm shims or ambiguous binaries' {
        Update-StandaloneCodex -Path '/fixture/codex.cmd'
        Update-StandaloneCodex -Path '/other-manager/codex.exe'
        Should -Invoke Invoke-DeveloperCommand -Times 0
        Should -Invoke Write-LogWarning -Times 1
    }

    It 'reports an unrecognized command shim without executing it' {
        Mock Get-Content { 'custom command wrapper' }
        Update-StandaloneCodex -Path '/fixture/codex.cmd'
        Should -Invoke Invoke-DeveloperCommand -Times 0
        Should -Invoke Write-LogWarning -Times 1
    }

    It 'does not invoke self-update in DryRun' {
        Update-StandaloneCodex -Path '/fixture/codex.exe' -DryRun
        Should -Invoke Invoke-DeveloperCommand -Times 0
    }
}


AfterAll {
    if ($script:AddedCimStub) { Remove-Item Function:/Get-CimInstance }
    if ($script:AddedSignatureStub) { Remove-Item Function:/Get-AuthenticodeSignature }
}

Describe 'Official Windows installer boundary' {
    BeforeEach {
        $script:NvmAffectedRoots = @('/fixture/nvm')
        Mock Invoke-RestMethod {
            @{ tag_name = 'v2.0.1'; draft = $false; prerelease = $false; assets = @(
                @{ name = 'nvm-2.0.1-x64-setup.exe'; browser_download_url = 'https://github.com/nvm-windows/nvm/releases/download/v2.0.1/nvm-2.0.1-x64-setup.exe' },
                @{ name = 'nvm-2.0.1-arm64-setup.exe'; browser_download_url = 'https://github.com/nvm-windows/nvm/releases/download/v2.0.1/nvm-2.0.1-arm64-setup.exe' }
            ) }
        }
        Mock Invoke-WebRequest {}
        Mock Get-AuthenticodeSignature { @{ Status = 'Valid'; SignerCertificate = @{ Subject = 'fixture publisher' } } }
        Mock Assert-NvmProcessesStopped {}
        Mock Start-Process { @{ ExitCode = 0 } }
    }

    It 'uses a stable official architecture asset and validates its signature before silent setup' {
        Install-NvmRelease
        Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $Uri -like 'https://github.com/nvm-windows/nvm/releases/download/v2.0.1/nvm-2.0.1-*-setup.exe' }
        Should -Invoke Get-AuthenticodeSignature -Times 1
        Should -Invoke Assert-NvmProcessesStopped -Times 1
        Should -Invoke Start-Process -Times 1 -ParameterFilter { $Wait -and $PassThru -and $ArgumentList -match '/VERYSILENT' -and $ArgumentList -match '/NOCLOSEAPPLICATIONS' }
    }

    It 'rejects an unsigned installer without executing it' {
        Mock Get-AuthenticodeSignature { @{ Status = 'NotSigned'; SignerCertificate = $null } }
        { Install-NvmRelease } | Should -Throw '*signature*'
        Should -Invoke Start-Process -Times 0
    }

    It 'rejects prereleases before downloading' {
        Mock Invoke-RestMethod { @{ tag_name = 'v2.0.2-beta.1'; prerelease = $true } }
        { Install-NvmRelease } | Should -Throw '*stable*'
        Should -Invoke Invoke-WebRequest -Times 0
    }

    It 'rejects an asset from a different source' {
        Mock Invoke-RestMethod { @{ tag_name = 'v2.0.1'; assets = @(@{ name = 'nvm-2.0.1-x64-setup.exe'; browser_download_url = 'https://untrusted.invalid/setup.exe' }) } }
        { Install-NvmRelease } | Should -Throw '*asset*'
        Should -Invoke Invoke-WebRequest -Times 0
    }

    It 'propagates installer failure' {
        Mock Start-Process { @{ ExitCode = 1 } }
        { Install-NvmRelease } | Should -Throw '*installer failed*'
    }

    It 'rechecks running processes immediately before launch' {
        Mock Assert-NvmProcessesStopped { throw 'new process started' }
        { Install-NvmRelease } | Should -Throw '*new process*'
        Should -Invoke Start-Process -Times 0
    }
}

Describe 'Verified nvm 2.x LTS selection' {
    BeforeEach {
        $script:PreviousLocalAppData2 = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $TestDrive
        $script:StateCalls = 0
        Mock Write-LogInfo {}
        Mock Write-LogWarning {}
        Mock Get-Command { @{ Source = 'fixture-nvm.exe' } } -ParameterFilter { $Name -eq 'nvm.exe' }
        Mock Get-NvmState {
            $script:StateCalls++
            $runtimes = @{ '20.0.0' = @{ Node = 'old-node'; Cli = 'old-cli'; Hash = 'same'; Packages = @{ tool = @{ version = '1.0.0'; link = $null } } } }
            if ($script:StateCalls -ge 3) { $runtimes['24.0.0'] = @{ Node = 'lts-node'; Cli = 'lts-cli'; Hash = 'new'; Packages = @{} } }
            @{ Version = '2.0.1'; Major = 2; Root = '/fixture/nvm/installs'; ProgramRoot = '/fixture/nvm'; Active = '20.0.0'; Runtimes = $runtimes }
        }
        Mock Test-Path { $true }
        Mock Assert-NvmProcessesStopped {}
        Mock Save-NvmRecovery {}
        Mock Install-NvmRelease {}
        Mock Update-ProcessEnvironment {}
        Mock Invoke-RestMethod { @(@{ version = 'v24.0.0'; lts = 'Fixture' }) }
        Mock Invoke-DeveloperCommand {
            param($FilePath, $Arguments)
            if ($Arguments[0] -eq 'default') { return '{"default":"v24.0.0"}' }
            if ($FilePath -eq 'lts-node' -and $Arguments[0] -eq '--version') { return 'v24.0.0' }
            return ''
        }
        Mock Invoke-NpmWorker { @{} }
    }
    AfterEach { $env:LOCALAPPDATA = $script:PreviousLocalAppData2 }

    It 'uses the supported updater, verifies retained packages, migrates globals then sets the default' {
        $runtime = Update-NvmRuntime
        $runtime.Node | Should -Be 'lts-node'
        Should -Invoke Install-NvmRelease -Times 0
        Should -Invoke Invoke-DeveloperCommand -Times 1 -ParameterFilter { $Arguments[0] -eq 'upgrade' }
        Should -Invoke Invoke-NpmWorker -Times 1 -ParameterFilter { $Action -eq 'verify' -and $Node -eq 'old-node' }
        Should -Invoke Invoke-NpmWorker -Times 1 -ParameterFilter { $Action -eq 'migrate' -and $Node -eq 'lts-node' -and $Packages.tool.version -eq '1.0.0' }
        Should -Invoke Invoke-DeveloperCommand -Times 1 -ParameterFilter { $Arguments[0] -eq 'use' -and $Arguments[1] -eq '24.0.0' -and $Arguments[2] -eq '--no-install' }
    }

    It 'does not switch the default if package migration fails' {
        Mock Invoke-NpmWorker { throw 'migration failed' } -ParameterFilter { $Action -eq 'migrate' }
        { Update-NvmRuntime } | Should -Throw '*migration failed*'
        Should -Invoke Invoke-DeveloperCommand -Times 0 -ParameterFilter { $Arguments[0] -eq 'use' }
    }
}

Describe 'Standalone Codex update contract' {
    BeforeEach {
        Mock Write-LogInfo {}
        Mock Write-LogWarning {}
        Mock Get-StandaloneCodexRoot { '/fixture/standalone' }
        Mock Invoke-DeveloperCommand {
            param($FilePath, $Arguments)
            if ($Arguments[0] -eq '--help') { return 'update    Apply update' }
            if ($Arguments[0] -eq '--version') { return 'codex-cli 1.0.0' }
            return ''
        }
        Mock Invoke-WebRequest {}
        Mock Get-Process { @{ Path = 'fixture-powershell.exe' } }
    }

    It 'updates a recognized standalone release and verifies the original command location' {
        Update-StandaloneCodex -Path '/fixture/bin/codex.exe'
        Should -Invoke Invoke-DeveloperCommand -Times 1 -ParameterFilter { $Arguments[0] -eq 'update' -and $FilePath -eq '/fixture/bin/codex.exe' }
        Should -Invoke Invoke-DeveloperCommand -Times 1 -ParameterFilter { $Arguments[0] -eq '--version' }
        Should -Invoke Invoke-WebRequest -Times 0
    }

    It 'uses the official unattended installer for an older recognized release without policy bypass' {
        $saved = [Environment]::GetEnvironmentVariable('CODEX_INSTALL_DIR', 'Process')
        Mock Invoke-DeveloperCommand { 'Usage: codex' } -ParameterFilter { $Arguments[0] -eq '--help' }
        Update-StandaloneCodex -Path '/fixture/bin/codex.exe'
        Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $Uri -eq 'https://chatgpt.com/codex/install.ps1' }
        Should -Invoke Invoke-DeveloperCommand -Times 1 -ParameterFilter {
            $FilePath -eq 'fixture-powershell.exe' -and $Arguments[0] -eq '-NoProfile' -and $Arguments[1] -eq '-NonInteractive' -and
            $Arguments[2] -eq '-File' -and ($Arguments -join ' ') -notmatch 'ExecutionPolicy'
        }
        [Environment]::GetEnvironmentVariable('CODEX_INSTALL_DIR', 'Process') | Should -Be $saved
    }

    It 'treats a failed self-update as an error without trying another installer' {
        Mock Invoke-DeveloperCommand { throw 'self-update failed' } -ParameterFilter { $Arguments[0] -eq 'update' }
        { Update-StandaloneCodex -Path '/fixture/bin/codex.exe' } | Should -Throw '*self-update failed*'
        Should -Invoke Invoke-WebRequest -Times 0
    }

    It 'rejects invalid version verification' {
        Mock Invoke-DeveloperCommand { 'unexpected output' } -ParameterFilter { $Arguments[0] -eq '--version' }
        { Update-StandaloneCodex -Path '/fixture/bin/codex.exe' } | Should -Throw '*verification*'
    }
}
