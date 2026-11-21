#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Unit-level coverage of the public orchestrator. The private checks and
# Get-ClusterInventory are mocked, so this file does not need a kubectl
# binary or a cluster — it asserts only the wiring: every check is called,
# findings aggregate correctly, the summary shape is right, and the
# -ExcludeNamespace parameter reaches Test-NamespaceLabels.

BeforeAll {
    $root        = Resolve-Path "$PSScriptRoot/../.."
    $privateRoot = Join-Path $root 'src/IstioAmbientPreflight/Private'
    $publicRoot  = Join-Path $root 'src/IstioAmbientPreflight/Public'

    . (Join-Path $privateRoot 'Format-Finding.ps1')

    # Stand-in declarations so Pester's Mock can replace them. Real
    # implementations are not dot-sourced here; we want the orchestrator
    # to call our mocks, not the actual checks.
    function Get-ClusterInventory             { param($Context) }
    function Test-NamespaceLabels             { param($Inventory, $Namespace, $ExcludeNamespace) }
    function Test-PodLabels                   { param($Inventory, $Namespace) }
    function Test-CiliumPolicyCompatibility   { param($Inventory) }
    function Test-GatewayConflict             { param($Inventory, $Namespace) }
    function New-AmbientMigrationReport       { param($Findings, $OutputPath, $Context) }

    . (Join-Path $publicRoot 'Invoke-AmbientPreflight.ps1')

    function New-EmptyInventory {
        [pscustomobject]@{
            Namespaces            = @()
            Pods                  = @()
            IstioGateways         = @()
            VirtualServices       = @()
            DestinationRules      = @()
            CiliumNetworkPolicies = @()
            GatewayAPIGateways    = @()
        }
    }

    function New-Finding {
        param(
            [Parameter(Mandatory)][string]$Severity,
            [Parameter(Mandatory)][string]$CheckId,
            [Parameter(Mandatory)][string]$Resource
        )
        Format-Finding `
            -Severity $Severity `
            -Category 'Test' `
            -CheckId  $CheckId `
            -Resource $Resource `
            -Message  'fixture finding' `
            -DocLink  'https://istio.io/latest/docs/ambient/'
    }
}

Describe 'Invoke-AmbientPreflight' {

    BeforeEach {
        $script:tempDir    = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())) -Force
        $script:reportPath = Join-Path $script:tempDir 'report.md'

        Mock Get-ClusterInventory { New-EmptyInventory }

        # Each check returns a deterministic finding so we can assert the
        # aggregator both calls every check and preserves their output.
        Mock Test-NamespaceLabels {
            New-Finding -Severity 'Warning' -CheckId 'N-01' -Resource 'Namespace/demo-app'
        }
        Mock Test-PodLabels {
            New-Finding -Severity 'Info'    -CheckId 'P-01' -Resource 'Pod/legacy-tls in namespace payments'
        }
        Mock Test-CiliumPolicyCompatibility {
            New-Finding -Severity 'Blocker' -CheckId 'C-02' -Resource 'CiliumNetworkPolicy/np in namespace payments'
        }
        Mock Test-GatewayConflict {
            New-Finding -Severity 'Warning' -CheckId 'G-02' -Resource 'VirtualService/vs in namespace payments'
        }
        Mock New-AmbientMigrationReport {
            param($Findings, $OutputPath, $Context)
            # Write a minimal file so callers that Test-Path on the result work.
            Set-Content -LiteralPath $OutputPath -Value '# stub report'
            $OutputPath
        }
    }

    AfterEach {
        if ($script:tempDir -and (Test-Path -LiteralPath $script:tempDir)) {
            Remove-Item -LiteralPath $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'invokes every compatibility check exactly once' {
        Invoke-AmbientPreflight -OutputPath $script:reportPath | Out-Null

        Should -Invoke Get-ClusterInventory           -Times 1 -Exactly
        Should -Invoke Test-NamespaceLabels           -Times 1 -Exactly
        Should -Invoke Test-PodLabels                 -Times 1 -Exactly
        Should -Invoke Test-CiliumPolicyCompatibility -Times 1 -Exactly
        Should -Invoke Test-GatewayConflict           -Times 1 -Exactly
        Should -Invoke New-AmbientMigrationReport     -Times 1 -Exactly
    }

    It 'aggregates findings from every check into the result object' {
        $result = Invoke-AmbientPreflight -OutputPath $script:reportPath

        $result.FindingCount | Should -Be 4
        $result.BlockerCount | Should -Be 1
        $result.WarningCount | Should -Be 2
        $result.InfoCount    | Should -Be 1

        $ids = $result.Findings | ForEach-Object CheckId | Sort-Object
        $ids | Should -Be @('C-02', 'G-02', 'N-01', 'P-01')
    }

    It 'returns the absolute report path on the result' {
        $result = Invoke-AmbientPreflight -OutputPath $script:reportPath

        $result.ReportPath | Should -Be $script:reportPath
        Test-Path -LiteralPath $result.ReportPath | Should -BeTrue
    }

    It 'passes -ExcludeNamespace through to Test-NamespaceLabels only' {
        Invoke-AmbientPreflight -OutputPath $script:reportPath `
            -ExcludeNamespace 'argocd', 'monitoring' | Out-Null

        Should -Invoke Test-NamespaceLabels -Times 1 -Exactly -ParameterFilter {
            $ExcludeNamespace -and
            ($ExcludeNamespace -contains 'argocd') -and
            ($ExcludeNamespace -contains 'monitoring')
        }

        # The pod and policy checks have no -ExcludeNamespace parameter,
        # so they must still receive only the inventory (and possibly
        # -Namespace), without -ExcludeNamespace leaking into them.
        Should -Invoke Test-PodLabels -Times 1 -Exactly
        Should -Invoke Test-CiliumPolicyCompatibility -Times 1 -Exactly
    }

    It 'passes -Namespace through to namespace and pod checks when supplied' {
        Invoke-AmbientPreflight -OutputPath $script:reportPath -Namespace 'payments' | Out-Null

        Should -Invoke Test-NamespaceLabels -Times 1 -Exactly -ParameterFilter {
            $Namespace -eq 'payments'
        }
        Should -Invoke Test-PodLabels -Times 1 -Exactly -ParameterFilter {
            $Namespace -eq 'payments'
        }
        Should -Invoke Test-GatewayConflict -Times 1 -Exactly -ParameterFilter {
            $Namespace -eq 'payments'
        }
    }

    It 'returns a Ready summary (zero findings) when every check is silent' {
        Mock Test-NamespaceLabels             { }
        Mock Test-PodLabels                   { }
        Mock Test-CiliumPolicyCompatibility   { }
        Mock Test-GatewayConflict             { }

        $result = Invoke-AmbientPreflight -OutputPath $script:reportPath

        $result.FindingCount | Should -Be 0
        $result.BlockerCount | Should -Be 0
        $result.WarningCount | Should -Be 0
        $result.InfoCount    | Should -Be 0
        $result.Findings     | Should -BeNullOrEmpty
    }
}
