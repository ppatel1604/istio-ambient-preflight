#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Fixture-specific end-to-end assertions. Runs Invoke-AmbientPreflight
# against a cluster prepared by tests/Integration/fixtures/setup-fixtures.sh
# and asserts that every shipped check fires on exactly the fixture
# resource it is meant to, and that the negative controls stay silent.
#
# Opt-in: skipped unless IAP_FIXTURE_CLUSTER=1, because on any other
# cluster the expected findings would not exist. The integration workflow
# sets it after running setup-fixtures.sh.

BeforeDiscovery {
    $script:fixtureCluster = $env:IAP_FIXTURE_CLUSTER -eq '1'
}

BeforeAll {
    $script:fixtureCluster = $env:IAP_FIXTURE_CLUSTER -eq '1'
    if (-not $script:fixtureCluster) { return }

    $manifest = Resolve-Path "$PSScriptRoot/../../src/IstioAmbientPreflight/IstioAmbientPreflight.psd1"
    Import-Module $manifest -Force

    $script:reportPath = Join-Path ([System.IO.Path]::GetTempPath()) ("iap-fixtures-" + [guid]::NewGuid() + '.md')
    $script:result = Invoke-AmbientPreflight `
        -ExcludeNamespace local-path-storage, default `
        -OutputPath $script:reportPath 6> $null

    function Get-FindingFor {
        param([string]$CheckId, [string]$Resource)
        @($script:result.Findings | Where-Object { $_.CheckId -eq $CheckId -and $_.Resource -eq $Resource })
    }
}

AfterAll {
    if ($script:reportPath -and (Test-Path -LiteralPath $script:reportPath)) {
        Remove-Item -LiteralPath $script:reportPath -Force -ErrorAction SilentlyContinue
    }
    Remove-Module IstioAmbientPreflight -Force -ErrorAction SilentlyContinue
}

Describe 'Fixture cluster findings' -Skip:(-not $script:fixtureCluster) {

    It '<CheckId> fires on <Resource>' -ForEach @(
        @{ CheckId = 'N-01'; Resource = 'Namespace/unlabeled-app' }
        @{ CheckId = 'N-02'; Resource = 'Namespace/legacy-injection' }
        @{ CheckId = 'P-01'; Resource = 'Pod/opt-out-pod in namespace payments' }
        @{ CheckId = 'P-02'; Resource = 'Pod/legacy-pod in namespace legacy-injection' }
        @{ CheckId = 'C-01'; Resource = 'CiliumNetworkPolicy/pod-only-no-15008 in namespace payments' }
        @{ CheckId = 'C-02'; Resource = 'CiliumNetworkPolicy/pod-only-no-15008 in namespace payments' }
        @{ CheckId = 'G-01'; Resource = 'Gateway/shop-legacy in namespace payments (Istio) + Gateway/shop-gw in namespace payments (Gateway API)' }
        @{ CheckId = 'G-02'; Resource = 'VirtualService/shop-routes in namespace payments' }
    ) {
        (Get-FindingFor -CheckId $CheckId -Resource $Resource).Count | Should -Be 1
    }

    It 'G-02 names the missing gateway' {
        $f = Get-FindingFor -CheckId 'G-02' -Resource 'VirtualService/shop-routes in namespace payments'
        $f[0].Message | Should -Match "'payments/retired-gateway'"
    }

    It 'emits nothing for the negative-control CiliumNetworkPolicy' {
        @($script:result.Findings | Where-Object { $_.Resource -like '*waypoint-allowed*' }).Count | Should -Be 0
    }

    It 'emits nothing for the mesh-only VirtualService' {
        @($script:result.Findings | Where-Object { $_.Resource -like '*internal-routes*' }).Count | Should -Be 0
    }

    It 'reports exactly the expected severity totals' {
        $script:result.BlockerCount | Should -Be 4
        $script:result.WarningCount | Should -Be 2
        $script:result.InfoCount    | Should -Be 2
    }

    It 'writes a Blocked verdict to the report' {
        Get-Content -LiteralPath $script:result.ReportPath -Raw | Should -Match '\*\*Verdict:\*\* Blocked'
    }
}
