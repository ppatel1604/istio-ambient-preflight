#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $privateRoot = Resolve-Path "$PSScriptRoot/../../src/IstioAmbientPreflight/Private"
    . (Join-Path $privateRoot 'Format-Finding.ps1')
    . (Join-Path $privateRoot 'Test-CiliumPolicyCompatibility.ps1')

    function New-Ns {
        param(
            [string]$Name,
            [string]$DataplaneMode
        )
        $labelsObj = $null
        if ($PSBoundParameters.ContainsKey('DataplaneMode')) {
            $labelsObj = [pscustomobject]@{ 'istio.io/dataplane-mode' = $DataplaneMode }
        }
        [pscustomobject]@{
            metadata = [pscustomobject]@{
                name   = $Name
                labels = $labelsObj
            }
        }
    }

    # Shape mirrors `kubectl get ciliumnetworkpolicies -o json` items. The
    # fixture supports: no ingress section, ingress rules without toPorts,
    # and ingress rules with toPorts whose ports are Cilium's
    # { port: "15008"; protocol: TCP } shape (port is a *string* in Cilium's
    # schema — see docs.cilium.io/en/stable/security/policy/language/#layer-4-examples).
    function New-CiliumPolicy {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$Namespace,
            [object[]]$IngressRules
        )

        $spec = [ordered]@{}
        if ($PSBoundParameters.ContainsKey('IngressRules')) {
            $spec.ingress = @($IngressRules)
        }

        [pscustomobject]@{
            metadata = [pscustomobject]@{
                name      = $Name
                namespace = $Namespace
            }
            spec     = [pscustomobject]$spec
        }
    }

    function New-IngressRule {
        param([object[]]$ToPorts)
        $obj = [ordered]@{
            fromEndpoints = @(
                [pscustomobject]@{
                    matchLabels = [pscustomobject]@{ 'app' = 'frontend' }
                }
            )
        }
        if ($PSBoundParameters.ContainsKey('ToPorts')) {
            $obj.toPorts = @($ToPorts)
        }
        [pscustomobject]$obj
    }

    function New-ToPorts {
        param([Parameter(Mandatory)][object[]]$Ports)
        [pscustomobject]@{ ports = @($Ports) }
    }

    function New-Port {
        param(
            [Parameter(Mandatory)][string]$Port,
            [string]$Protocol = 'TCP'
        )
        [pscustomobject]@{
            port     = $Port
            protocol = $Protocol
        }
    }

    function New-Inventory {
        param(
            [object[]]$Namespaces           = @(),
            [object[]]$CiliumNetworkPolicies = @()
        )
        [pscustomobject]@{
            Namespaces            = @($Namespaces)
            CiliumNetworkPolicies = @($CiliumNetworkPolicies)
        }
    }
}

Describe 'Test-CiliumPolicyCompatibility (C-02)' {

    It 'emits no finding when the policy lives in a non-ambient namespace' {
        # 'payments' is unlabeled, so ambient migration has not yet enrolled it;
        # Cilium policies there are not mesh-affected and must not be flagged.
        $policy = New-CiliumPolicy -Name 'allow-frontend' -Namespace 'payments' `
            -IngressRules @(New-IngressRule -ToPorts @(New-ToPorts -Ports @(New-Port -Port '8080')))

        $inv = New-Inventory -Namespaces @(New-Ns -Name 'payments') `
            -CiliumNetworkPolicies @($policy)

        $findings = @(Test-CiliumPolicyCompatibility -Inventory $inv)

        $findings.Count | Should -Be 0
    }

    It 'emits no finding when an ambient-namespace policy has no ingress rules (egress-only policy)' {
        # A policy with no ingress section does not restrict ingress, so
        # ztunnel HBONE traffic on 15008 is implicitly permitted.
        $policy = New-CiliumPolicy -Name 'egress-to-db' -Namespace 'payments'

        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -DataplaneMode 'ambient') `
            -CiliumNetworkPolicies @($policy)

        $findings = @(Test-CiliumPolicyCompatibility -Inventory $inv)

        $findings.Count | Should -Be 0
    }

    It 'emits a Blocker when an ambient-namespace policy has ingress rules but does not allow TCP/15008' {
        $policy = New-CiliumPolicy -Name 'allow-frontend' -Namespace 'payments' `
            -IngressRules @(
                New-IngressRule -ToPorts @(
                    New-ToPorts -Ports @(
                        New-Port -Port '8080' -Protocol 'TCP'
                    )
                )
            )

        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -DataplaneMode 'ambient') `
            -CiliumNetworkPolicies @($policy)

        $findings = @(Test-CiliumPolicyCompatibility -Inventory $inv)

        $findings.Count       | Should -Be 1
        $findings[0].Severity | Should -Be 'Blocker'
        $findings[0].Category | Should -Be 'Network'
        $findings[0].CheckId  | Should -Be 'C-02'
        $findings[0].Resource | Should -Be 'CiliumNetworkPolicy/allow-frontend in namespace payments'
        $findings[0].DocLink  | Should -Be 'https://istio.io/latest/docs/ambient/architecture/traffic-redirection/'
        $findings[0].Message  | Should -Match '15008'
        $findings[0].Message  | Should -Match 'ztunnel'
    }

    It 'emits no finding when an ambient-namespace policy explicitly allows TCP/15008' {
        $policy = New-CiliumPolicy -Name 'allow-mesh' -Namespace 'payments' `
            -IngressRules @(
                New-IngressRule -ToPorts @(
                    New-ToPorts -Ports @(
                        New-Port -Port '8080'  -Protocol 'TCP'
                        New-Port -Port '15008' -Protocol 'TCP'
                    )
                )
            )

        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -DataplaneMode 'ambient') `
            -CiliumNetworkPolicies @($policy)

        $findings = @(Test-CiliumPolicyCompatibility -Inventory $inv)

        $findings.Count | Should -Be 0
    }

    It 'returns zero findings and no error when CiliumNetworkPolicies is empty (CRD not installed)' {
        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -DataplaneMode 'ambient') `
            -CiliumNetworkPolicies @()

        { Test-CiliumPolicyCompatibility -Inventory $inv } | Should -Not -Throw

        $findings = @(Test-CiliumPolicyCompatibility -Inventory $inv)
        $findings.Count | Should -Be 0
    }
}
