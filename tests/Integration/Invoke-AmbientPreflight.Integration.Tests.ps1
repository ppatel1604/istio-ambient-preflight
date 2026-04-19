#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# End-to-end smoke test. Imports the module the same way a user would and runs
# Invoke-AmbientPreflight against the current kubectl context. Skips (not fails)
# if kubectl is missing or no cluster is reachable, so this file is safe to run
# from a developer workstation without a cluster handy. CI can opt in to this
# leg via a separate workflow once a kind-based integration harness is wired up.

BeforeAll {
    $manifest = Resolve-Path "$PSScriptRoot/../../src/IstioAmbientPreflight/IstioAmbientPreflight.psd1"
    Import-Module $manifest -Force

    $script:hasKubectl       = [bool](Get-Command kubectl -ErrorAction SilentlyContinue)
    $script:clusterReachable = $false
    if ($script:hasKubectl) {
        & kubectl cluster-info --request-timeout=3s *> $null
        $script:clusterReachable = ($LASTEXITCODE -eq 0)
    }

    $script:reportPath = Join-Path ([System.IO.Path]::GetTempPath()) ("iap-integration-" + [guid]::NewGuid() + '.md')
}

AfterAll {
    if (Test-Path -LiteralPath $script:reportPath) {
        Remove-Item -LiteralPath $script:reportPath -Force -ErrorAction SilentlyContinue
    }
    Remove-Module IstioAmbientPreflight -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-AmbientPreflight end-to-end' {

    It 'produces a markdown report against the current cluster' {
        if (-not ($script:hasKubectl -and $script:clusterReachable)) {
            Set-ItResult -Skipped -Because 'kubectl is missing or no cluster is reachable'
            return
        }

        $result = Invoke-AmbientPreflight -OutputPath $script:reportPath

        $result                          | Should -Not -BeNullOrEmpty
        $result.ReportPath               | Should -Be (Resolve-Path -LiteralPath $script:reportPath).Path
        Test-Path -LiteralPath $result.ReportPath | Should -BeTrue

        $content = Get-Content -LiteralPath $result.ReportPath -Raw
        $content | Should -Match '# Istio Ambient Preflight Report'
        $content | Should -Match '## Summary'
        $content | Should -Match '\*\*Verdict:\*\*'

        # The result object exposes the canonical counts.
        ($result.FindingCount -is [int])  | Should -BeTrue
        ($result.BlockerCount + $result.WarningCount + $result.InfoCount) | Should -Be $result.FindingCount
    }
}
