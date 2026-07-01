BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:VersionModule = Join-Path $script:RepoRoot 'windows/lib/VersionCheck.psm1'
    $script:VersionAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:VersionModule,
        [ref]$null,
        [ref]$null
    )
}

Describe 'VersionCheck side effects' {
    It 'requires explicit opt-in for git fetch' {
        Import-Module $script:VersionModule -Force

        (Get-Command Test-ForUpdates).Parameters.Keys | Should -Contain 'Fetch'
    }

    It 'keeps git fetch guarded by the Fetch switch' {
        $functionAst = $script:VersionAst.Find({
            param($Node)
            $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $Node.Name -eq 'Test-ForUpdates'
        }, $true)

        $fetchBlock = $functionAst.Find({
            param($Node)
            $Node -is [System.Management.Automation.Language.IfStatementAst] -and
            $Node.Extent.Text -match '\bgit\b' -and
            $Node.Extent.Text -match '\bfetch\b'
        }, $true)

        $fetchBlock | Should -Not -BeNullOrEmpty
        $fetchBlock.Clauses[0].Item1.Extent.Text | Should -Be '$Fetch'
    }
}
