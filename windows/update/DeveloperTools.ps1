# Internal helpers loaded by Update-System.ps1 (PowerShell 5.1 and 7).
function Invoke-DeveloperCommand {
    [CmdletBinding()]
    param([string]$FilePath, [string[]]$Arguments)
    $output = & $FilePath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Developer-tool command failed; dependent updates stopped.' }
    return ($output | Out-String).Trim()
}

function Invoke-NpmWorker {
    [CmdletBinding()]
    param([string]$Node, [string]$Cli, [string]$Action, $Packages, [switch]$UpdateNpm, [switch]$UpdateCodex, [switch]$Cleanup, [switch]$Clean)
    $worker = Join-Path (Split-Path (Split-Path $Script:ScriptDir -Parent) -Parent) 'shared/npm-tools.cjs'
    $inputData = @{ cli = $Cli; action = $Action; packages = $Packages; npm = [bool]$UpdateNpm; codex = [bool]$UpdateCodex; cleanup = [bool]$Cleanup; clean = [bool]$Clean } | ConvertTo-Json -Depth 30 -Compress
    $output = $inputData | & $Node $worker 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'npm inventory, update, or preservation verification failed.' }
    return (($output | Out-String) | ConvertFrom-Json -ErrorAction Stop)
}

function Get-NpmRuntime {
    [CmdletBinding()]
    param([string]$Node)
    if (-not $Node) {
        $command = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue
        if (-not $command) { return $null }
        Push-Location -LiteralPath $env:USERPROFILE
        try { $Node = Invoke-DeveloperCommand $command.Source @('-p', 'process.execPath') } finally { Pop-Location }
        if (-not [IO.Path]::IsPathRooted($Node) -or -not (Test-Path -LiteralPath $Node -PathType Leaf)) { throw 'Cannot resolve selected Node executable.' }
    }
    # Use npm's JS entry point, bypassing neither PowerShell policy nor cmd quoting.
    $cli = Join-Path (Split-Path $Node -Parent) 'node_modules/npm/bin/npm-cli.js'
    if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) {
        $npm = Get-Command npm.cmd -CommandType Application -ErrorAction SilentlyContinue
        if (-not $npm) { return $null }
        $cli = Join-Path (Split-Path $npm.Source -Parent) 'node_modules/npm/bin/npm-cli.js'
    }
    if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) { throw 'Cannot resolve the installed npm CLI.' }
    return @{ Node = $Node; Cli = $cli }
}

function Update-ProcessEnvironment {
    [CmdletBinding()]
    param()
    # The installer changes user environment in the registry, not this process.
    foreach ($name in @('NVM_HOME', 'NVM_SYMLINK')) {
        $value = [Environment]::GetEnvironmentVariable($name, 'User')
        if ($value) { [Environment]::SetEnvironmentVariable($name, $value, 'Process') }
    }
    $paths = @([Environment]::GetEnvironmentVariable('Path', 'User'), [Environment]::GetEnvironmentVariable('Path', 'Machine'), $env:Path)
    $env:Path = [Environment]::ExpandEnvironmentVariables(($paths | Where-Object { $_ }) -join ';')
}

function Get-NvmState {
    [CmdletBinding()]
    param([string]$Nvm)
    $version = Invoke-DeveloperCommand $Nvm @('version')
    if ($version -notmatch '^v?(\d+)\.\d+\.\d+(?:-[\w.-]+)?$') { throw 'Invalid nvm version.' }
    $major = [int]$Matches[1]
    $programRoot = Split-Path $Nvm -Parent
    $configuration = $null
    $active = $null
    $linkRoot = $env:NVM_SYMLINK
    if ($major -ge 2) {
        $configuration = Get-ItemProperty -LiteralPath 'HKCU:\Software\Author Software\Preferences\nvm' -ErrorAction Stop
        $root = [Environment]::ExpandEnvironmentVariables($configuration.InstallRoot)
        $active = $configuration.ActiveVersion
    } else {
        $settings = Join-Path $programRoot 'settings.txt'
        $configuration = Get-Content -LiteralPath $settings -Raw -ErrorAction Stop
        if ($configuration -notmatch '(?m)^root:\s*(.+?)\s*$') { throw 'Missing legacy nvm root.' }
        $root = $Matches[1].Trim()
        if ($configuration -match '(?m)^path:\s*(.+?)\s*$') { $linkRoot = $Matches[1].Trim() }
        $current = Invoke-DeveloperCommand $Nvm @('current')
        if ($current -match '^v?(\d+\.\d+\.\d+)$') { $active = $Matches[1] }
    }
    if (-not [IO.Path]::IsPathRooted($root) -or -not (Test-Path -LiteralPath $root -PathType Container)) {
        throw 'Cannot resolve nvm runtime root.'
    }
    $runtimes = @{}
    foreach ($directory in Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop) {
        if ($directory.Name -notmatch '^v?(\d+\.\d+\.\d+)$') { continue }
        $runtimeVersion = $Matches[1]
        $node = Join-Path $directory.FullName 'node.exe'
        if (-not (Test-Path -LiteralPath $node -PathType Leaf)) { throw 'Installed runtime is incomplete.' }
        $runtime = Get-NpmRuntime -Node $node
        if (-not $runtime) { throw 'Installed runtime npm is missing.' }
        $runtimes[$runtimeVersion] = @{
            Node = $node; Cli = $runtime.Cli
            Hash = (Get-FileHash -LiteralPath $node -Algorithm SHA256).Hash
            Packages = Invoke-NpmWorker @runtime -Action inventory
        }
    }
    if ($runtimes.Count -gt 0 -and (-not $active -or -not $runtimes.ContainsKey($active.TrimStart('v')))) {
        throw 'Cannot determine the existing default runtime.'
    }
    return @{ Version = $version.TrimStart('v'); Major = $major; ProgramRoot = $programRoot; Root = $root; LinkRoot = $linkRoot; Configuration = $configuration; Active = $active; Runtimes = $runtimes }
}

function Assert-NvmProcessesStopped {
    [CmdletBinding()]
    param([string[]]$Roots)
    # Fail closed when process enumeration fails. Never terminate a process.
    $processes = Get-CimInstance Win32_Process -ErrorAction Stop
    foreach ($process in $processes) {
        if (-not $process.ExecutablePath) {
            if ($process.Name -match '^(node|nvm|sync|codex)\.exe$') { throw 'Cannot inspect a potentially affected process; close developer tools and retry.' }
            continue
        }
        foreach ($root in $Roots) {
            if (-not $root) { continue }
            $prefix = [IO.Path]::GetFullPath($root).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            if ($process.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Developer processes are using nvm directories. Close them and retry; migration deferred.'
            }
        }
    }
}

function Save-NvmRecovery {
    [CmdletBinding()]
    param($State)
    $directory = Join-Path $env:LOCALAPPDATA ('SystemLifecycle/recovery/' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $directory -ErrorAction Stop
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User, [Security.Principal.SecurityIdentifier]'S-1-5-18')) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $directory -AclObject $acl -ErrorAction Stop
    $State | Export-Clixml -LiteralPath (Join-Path $directory 'nvm-before.xml') -Depth 40 -ErrorAction Stop
    Write-LogInfo 'Private nvm recovery inventory saved under LocalAppData/SystemLifecycle/recovery.'
}

function Install-NvmRelease {
    [CmdletBinding()]
    param()
    $release = Invoke-RestMethod 'https://api.github.com/repos/nvm-windows/nvm/releases/latest' -ErrorAction Stop
    if ($release.draft -or $release.prerelease -or $release.tag_name -notmatch '^v2\.\d+\.\d+$') {
        throw 'No supported stable nvm-windows 2.x release found.'
    }
    $architecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'x64' }
    $name = 'nvm-' + $release.tag_name.TrimStart('v') + '-' + $architecture + '-setup.exe'
    $expectedUrl = 'https://github.com/nvm-windows/nvm/releases/download/' + $release.tag_name + '/' + $name
    $asset = @($release.assets | Where-Object { $_.name -eq $name -and $_.browser_download_url -eq $expectedUrl })
    if ($asset.Count -ne 1) { throw 'Official nvm installer asset not found.' }
    $directory = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $directory -ErrorAction Stop
    try {
        $installer = Join-Path $directory $name
        Invoke-WebRequest -Uri $expectedUrl -OutFile $installer -UseBasicParsing -ErrorAction Stop
        $signature = Get-AuthenticodeSignature -LiteralPath $installer
        if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) { throw 'nvm installer signature is not valid.' }
        # Recheck immediately before launch: silent upstream setup can close apps.
        Assert-NvmProcessesStopped -Roots $Script:NvmAffectedRoots
        $process = Start-Process -FilePath $installer -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCLOSEAPPLICATIONS /NORESTARTAPPLICATIONS' -Wait -PassThru -ErrorAction Stop
        if ($process.ExitCode -ne 0) { throw 'nvm installer failed; inspect private recovery inventory.' }
    } finally {
        Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction Stop
    }
}

function Assert-NvmPreserved {
    [CmdletBinding()]
    param($Before, $After)
    foreach ($version in $Before.Runtimes.Keys) {
        if (-not $After.Runtimes.ContainsKey($version) -or $Before.Runtimes[$version].Hash -ne $After.Runtimes[$version].Hash) {
            throw 'An installed Node runtime was not preserved; dependent updates stopped.'
        }
        $runtime = $After.Runtimes[$version]
        $null = Invoke-NpmWorker -Node $runtime.Node -Cli $runtime.Cli -Action verify -Packages $Before.Runtimes[$version].Packages
    }
}

function Update-NvmRuntime {
    [CmdletBinding()]
    param([switch]$DryRun)
    $command = Get-Command nvm.exe -CommandType Application -ErrorAction SilentlyContinue
    if (-not $command) { return Get-NpmRuntime }
    if ($DryRun) { Write-LogInfo '[DRY-RUN] Would update installed nvm, preserve runtimes/globals, and select latest LTS.'; return $null }
    $before = Get-NvmState -Nvm $command.Source
    $Script:NvmAffectedRoots = @($before.ProgramRoot, $before.Root, $before.LinkRoot, (Join-Path $env:LOCALAPPDATA 'Author Software/nvm'))
    if ($before.Major -ge 2) { $Script:NvmAffectedRoots += Split-Path $before.Root -Parent }
    Assert-NvmProcessesStopped -Roots $Script:NvmAffectedRoots
    Save-NvmRecovery -State $before
    if ($before.Major -ge 2 -and (Test-Path -LiteralPath (Join-Path $before.ProgramRoot 'utils/sync.exe'))) {
        $null = Invoke-DeveloperCommand $command.Source @('upgrade')
    } else { Install-NvmRelease }
    Update-ProcessEnvironment
    $command = Get-Command nvm.exe -CommandType Application -ErrorAction Stop
    $after = Get-NvmState -Nvm $command.Source
    if ($after.Major -lt 2) { throw 'nvm migration was not verified.' }
    Assert-NvmPreserved -Before $before -After $after
    $releases = Invoke-RestMethod 'https://nodejs.org/dist/index.json' -ErrorAction Stop
    $latest = $releases | Where-Object { $_.lts } | Select-Object -First 1
    if ($latest.version -notmatch '^v\d+\.\d+\.\d+$') { throw 'Invalid Node LTS release metadata.' }
    $target = $latest.version.TrimStart('v')
    $null = Invoke-DeveloperCommand $command.Source @('install', $target)
    # Inspect the destination without switching the user's default first.
    $destination = Get-NvmState -Nvm $command.Source
    if (-not $destination.Runtimes.ContainsKey($target)) { throw 'LTS runtime installation was not verified.' }
    $runtime = $destination.Runtimes[$target]
    if ($before.Active) {
        $null = Invoke-NpmWorker -Node $runtime.Node -Cli $runtime.Cli -Action migrate -Packages $before.Runtimes[$before.Active.TrimStart('v')].Packages
    }
    $null = Invoke-DeveloperCommand $command.Source @('use', $target, '--no-install')
    Update-ProcessEnvironment
    $default = (Invoke-DeveloperCommand $command.Source @('default', '--json')) | ConvertFrom-Json -ErrorAction Stop
    if ($default.default.TrimStart('v') -ne $target -or (Invoke-DeveloperCommand $runtime.Node @('--version')) -ne $latest.version) {
        throw 'Node default verification failed.'
    }
    return @{ Node = $runtime.Node; Cli = $runtime.Cli }
}

function Update-NpmPackages {
    [CmdletBinding()]
    param([switch]$DryRun, [switch]$Skip, [switch]$NoCodex, [switch]$Clean, $Runtime)
    if ($Skip -and $NoCodex) { return }
    if ($DryRun) { Write-LogInfo '[DRY-RUN] Would update installed npm/global tools and npm-managed Codex according to controls.'; return }
    if (-not $Runtime) { $Runtime = Get-NpmRuntime }
    if ($Runtime) { $null = Invoke-NpmWorker @Runtime -Action update -UpdateNpm:(-not $Skip) -UpdateCodex:(-not $NoCodex) -Cleanup:(-not $Skip) -Clean:$Clean }
}

function Get-StandaloneCodexRoot {
    [CmdletBinding()]
    param([string]$Path)
    # Official Windows visible bin is a junction into packages/standalone.
    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    $root = [IO.Path]::GetFullPath((Join-Path $codexHome 'packages/standalone'))
    $item = Get-Item -LiteralPath (Split-Path $Path -Parent) -ErrorAction Stop
    $target = @($item.Target) | Select-Object -First 1
    if (-not $target) { return $null }
    if (-not [IO.Path]::IsPathRooted($target)) { $target = Join-Path $item.Parent.FullName $target }
    $target = [IO.Path]::GetFullPath($target)
    if (-not $target.StartsWith($root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $null }
    return $root
}

function Update-StandaloneCodex {
    [CmdletBinding()]
    param([switch]$DryRun, [string]$Path)
    if (-not $Path) { return }
    if ($DryRun) { Write-LogInfo '[DRY-RUN] Would update recognized standalone Codex in its existing directory.'; return }
    if ([IO.Path]::GetExtension($Path) -in @('.cmd', '.ps1')) {
        $shim = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ($shim -notmatch 'node_modules[\\/]@openai[\\/]codex[\\/]') {
            Write-LogWarning 'Codex source is ambiguous; standalone update skipped.'
        }
        return
    }
    if ((Split-Path $Path -Leaf) -ne 'codex.exe') {
        Write-LogWarning 'Codex source is ambiguous; standalone update skipped.'
        return
    }
    $root = Get-StandaloneCodexRoot -Path $Path
    if (-not $root) {
        Write-LogWarning 'Codex source is ambiguous; standalone update skipped.'
        return
    }
    $helpText = Invoke-DeveloperCommand $Path @('--help')
    if ($helpText -match '(?m)^\s*update\s') {
        $previousDirectory = [Environment]::GetEnvironmentVariable('CODEX_INSTALL_DIR', 'Process')
        $previousInteractive = [Environment]::GetEnvironmentVariable('CODEX_NON_INTERACTIVE', 'Process')
        try {
            $env:CODEX_INSTALL_DIR = Split-Path $Path -Parent
            $env:CODEX_NON_INTERACTIVE = 'true'
            $null = Invoke-DeveloperCommand $Path @('update')
        } finally {
            foreach ($pair in @(@('CODEX_INSTALL_DIR', $previousDirectory), @('CODEX_NON_INTERACTIVE', $previousInteractive))) {
                if ($null -eq $pair[1]) { Remove-Item -LiteralPath ('Env:' + $pair[0]) -ErrorAction SilentlyContinue }
                else { [Environment]::SetEnvironmentVariable($pair[0], $pair[1], 'Process') }
            }
        }
    } else {
        $temporary = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $temporary -ErrorAction Stop
        $saved = @{}
        $overrides = @{
            CODEX_INSTALL_DIR = Split-Path $Path -Parent
            CODEX_NON_INTERACTIVE = 'true'; CODEX_RELEASE = 'latest'
            CODEX_INSTALL_DAEMON_ONLY = '0'; CODEX_INSTALL_DEFER_SELECTION = '0'
        }
        try {
            $installer = Join-Path $temporary 'install.ps1'
            Invoke-WebRequest -Uri 'https://chatgpt.com/codex/install.ps1' -OutFile $installer -UseBasicParsing -ErrorAction Stop
            foreach ($name in $overrides.Keys) {
                $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
                [Environment]::SetEnvironmentVariable($name, $overrides[$name], 'Process')
            }
            $executable = (Get-Process -Id $PID).Path
            $null = Invoke-DeveloperCommand $executable @('-NoProfile', '-NonInteractive', '-File', $installer)
        } finally {
            foreach ($name in $saved.Keys) {
                if ($null -eq $saved[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
                else { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
            }
            Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction Stop
        }
    }
    $version = Invoke-DeveloperCommand $Path @('--version')
    if ($version -notmatch '^codex(?:-cli)? \d+\.\d+\.\d+(?:[-+][\w.-]+)?$' -or (Get-StandaloneCodexRoot -Path $Path) -ne $root) {
        throw 'Codex installation verification failed.'
    }
}
