#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $privateRoot = Resolve-Path "$PSScriptRoot/../../src/IstioAmbientPreflight/Private"
    . (Join-Path $privateRoot 'Format-Finding.ps1')
    . (Join-Path $privateRoot 'Test-NamespaceLabels.ps1')

    function New-Ns {
        param([string]$Name, [hashtable]$Labels)
        $labelsObj = $null
        if ($PSBoundParameters.ContainsKey('Labels')) {
            $labelsObj = [pscustomobject]$Labels
        }
        [pscustomobject]@{
            metadata = [pscustomobject]@{
                name   = $Name
                labels = $labelsObj
            }
        }
    }

    function New-Inventory {
        param([object[]]$Namespaces)
        [pscustomobject]@{ Namespaces = @($Namespaces) }
    }
}

Describe 'Test-NamespaceLabels (N-01)' {

    It 'emits a Warning finding when a namespace has no dataplane-mode label' {
        $inv = New-Inventory @(New-Ns -Name 'demo-app')

        $findings = @(Test-NamespaceLabels -Inventory $inv)

        $findings.Count            | Should -Be 1
        $findings[0].Severity      | Should -Be 'Warning'
        $findings[0].Category      | Should -Be 'Labels'
        $findings[0].CheckId       | Should -Be 'N-01'
        $findings[0].Resource      | Should -Be 'Namespace/demo-app'
        $findings[0].DocLink       | Should -Be 'https://istio.io/latest/docs/ambient/usage/add-workloads/'
        $findings[0].Message       | Should -Match "kubectl label namespace demo-app istio\.io/dataplane-mode=ambient"
    }

    It 'emits no finding when the namespace is labeled dataplane-mode=ambient' {
        $inv = New-Inventory @(New-Ns -Name 'payments' -Labels @{ 'istio.io/dataplane-mode' = 'ambient' })

        $findings = @(Test-NamespaceLabels -Inventory $inv)

        $findings.Count | Should -Be 0
    }

    It 'emits no finding when the namespace is explicitly opted out with dataplane-mode=none' {
        $inv = New-Inventory @(New-Ns -Name 'legacy' -Labels @{ 'istio.io/dataplane-mode' = 'none' })

        $findings = @(Test-NamespaceLabels -Inventory $inv)

        $findings.Count | Should -Be 0
    }

    It 'skips all documented system namespaces' {
        $systemNamespaces = @('kube-system', 'kube-public', 'kube-node-lease', 'istio-system', 'cilium')
        $inv = New-Inventory ($systemNamespaces | ForEach-Object { New-Ns -Name $_ })

        $findings = @(Test-NamespaceLabels -Inventory $inv)

        $findings.Count | Should -Be 0
    }

    It 'respects the -Namespace filter' {
        $inv = New-Inventory @(
            New-Ns -Name 'demo-app'
            New-Ns -Name 'payments'
            New-Ns -Name 'frontend'
        )

        $findings = @(Test-NamespaceLabels -Inventory $inv -Namespace 'payments')

        $findings.Count        | Should -Be 1
        $findings[0].Resource  | Should -Be 'Namespace/payments'
    }

    It 'flags a namespace with unrelated labels but no dataplane-mode label' {
        $inv = New-Inventory @(New-Ns -Name 'frontend' -Labels @{ 'team' = 'web'; 'env' = 'prod' })

        $findings = @(Test-NamespaceLabels -Inventory $inv)

        $findings.Count | Should -Be 1
    }

    It 'ignores a namespace with an unrecognized dataplane-mode value (treats as unset)' {
        $inv = New-Inventory @(New-Ns -Name 'weird' -Labels @{ 'istio.io/dataplane-mode' = 'sidecar-forever' })

        $findings = @(Test-NamespaceLabels -Inventory $inv)

        $findings.Count | Should -Be 1
    }

    It 'returns an empty array when the inventory has no namespaces' {
        $findings = @(Test-NamespaceLabels -Inventory (New-Inventory @()))
        $findings.Count | Should -Be 0
    }
}
