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
    # fixture supports: no ingress section, ingress rules with or without
    # toPorts, and ingress rules with or without fromEndpoints. Cilium's
    # port shape is { port: "15008"; protocol: TCP } -- port is a string
    # in Cilium's schema (see docs.cilium.io/en/stable/security/policy/
    # language/#layer-4-examples).
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

    # If -FromMatchLabels is omitted the rule has no fromEndpoints at all
    # (i.e. no source restriction); this keeps C-02-only tests focused on
    # the port aspect without accidentally tripping C-01.
    function New-IngressRule {
        param(
            [object[]]$ToPorts,
            [hashtable]$FromMatchLabels
        )
        $obj = [ordered]@{}
        if ($PSBoundParameters.ContainsKey('FromMatchLabels')) {
            $obj.fromEndpoints = @(
                [pscustomobject]@{ matchLabels = [pscustomobject]$FromMatchLabels }
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
        # No fromEndpoints on the rule (port-only), so this isolates the
        # C-02 concern from the C-01 source-identity concern.
        $policy = New-CiliumPolicy -Name 'allow-port' -Namespace 'payments' `
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
        $findings[0].Resource | Should -Be 'CiliumNetworkPolicy/allow-port in namespace payments'
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

Describe 'Test-CiliumPolicyCompatibility (C-01)' {

    It 'emits a Blocker when an ambient-namespace policy uses pod-selector ingress with no waypoint-identity label' {
        # Classic pre-ambient policy: "allow ingress from any pod with
        # app=frontend on port 15008" -- C-02 is satisfied (15008 is
        # admitted) but the source selector won't match the waypoint pod.
        $policy = New-CiliumPolicy -Name 'pod-only' -Namespace 'payments' `
            -IngressRules @(
                New-IngressRule `
                    -FromMatchLabels @{ 'app' = 'frontend' } `
                    -ToPorts @(New-ToPorts -Ports @(New-Port -Port '15008' -Protocol 'TCP'))
            )

        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -DataplaneMode 'ambient') `
            -CiliumNetworkPolicies @($policy)

        $findings = @(Test-CiliumPolicyCompatibility -Inventory $inv)

        $c01 = @($findings | Where-Object CheckId -eq 'C-01')
        $c01.Count       | Should -Be 1
        $c01[0].Severity | Should -Be 'Blocker'
        $c01[0].Category | Should -Be 'Network'
        $c01[0].Resource | Should -Be 'CiliumNetworkPolicy/pod-only in namespace payments'
        $c01[0].DocLink  | Should -Be 'https://istio.io/latest/docs/ambient/usage/waypoint/'
        $c01[0].Message  | Should -Match 'waypoint'
        $c01[0].Message  | Should -Match 'AuthorizationPolicy'
    }

    It 'emits no C-01 when fromEndpoints already selects the waypoint via istio.io/gateway-name' {
        # The operator has authored a policy that admits the waypoint
        # explicitly. The selector reflects ambient awareness, so C-01
        # has nothing to flag.
        $policy = New-CiliumPolicy -Name 'allow-waypoint' -Namespace 'payments' `
            -IngressRules @(
                New-IngressRule `
                    -FromMatchLabels @{ 'istio.io/gateway-name' = 'payments-waypoint' } `
                    -ToPorts @(New-ToPorts -Ports @(New-Port -Port '15008' -Protocol 'TCP'))
            )

        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -DataplaneMode 'ambient') `
            -CiliumNetworkPolicies @($policy)

        $findings = @(Test-CiliumPolicyCompatibility -Inventory $inv)

        ($findings | Where-Object CheckId -eq 'C-01').Count | Should -Be 0
    }

    It 'emits no C-01 when fromEndpoints includes the istio.io/waypoint-for label' {
        $policy = New-CiliumPolicy -Name 'allow-waypoint-for' -Namespace 'payments' `
            -IngressRules @(
                New-IngressRule `
                    -FromMatchLabels @{ 'istio.io/waypoint-for' = 'service' } `
                    -ToPorts @(New-ToPorts -Ports @(New-Port -Port '15008' -Protocol 'TCP'))
            )

        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -DataplaneMode 'ambient') `
            -CiliumNetworkPolicies @($policy)

        $findings = @(Test-CiliumPolicyCompatibility -Inventory $inv)

        ($findings | Where-Object CheckId -eq 'C-01').Count | Should -Be 0
    }

    It 'emits no C-01 in a non-ambient namespace, even when pod-selector ingress is present' {
        $policy = New-CiliumPolicy -Name 'pod-only' -Namespace 'legacy' `
            -IngressRules @(
                New-IngressRule `
                    -FromMatchLabels @{ 'app' = 'frontend' } `
                    -ToPorts @(New-ToPorts -Ports @(New-Port -Port '8080' -Protocol 'TCP'))
            )

        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'legacy') `
            -CiliumNetworkPolicies @($policy)

        $findings = @(Test-CiliumPolicyCompatibility -Inventory $inv)

        $findings.Count | Should -Be 0
    }

    It 'emits no C-01 when fromEndpoints matchLabels is empty (any-pod selector)' {
        # `fromEndpoints: [{}]` permits any endpoint -- waypoint-sourced
        # traffic matches as well. There is no pod-only restriction to flag.
        $policy = New-CiliumPolicy -Name 'allow-any' -Namespace 'payments' `
            -IngressRules @(
                New-IngressRule `
                    -FromMatchLabels @{} `
                    -ToPorts @(New-ToPorts -Ports @(New-Port -Port '15008' -Protocol 'TCP'))
            )

        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -DataplaneMode 'ambient') `
            -CiliumNetworkPolicies @($policy)

        $findings = @(Test-CiliumPolicyCompatibility -Inventory $inv)

        ($findings | Where-Object CheckId -eq 'C-01').Count | Should -Be 0
    }

    It 'emits no C-01 when the rule has no fromEndpoints at all (port-only restriction)' {
        # A port-only rule does not restrict source identity, so the
        # waypoint identity is implicitly admitted.
        $policy = New-CiliumPolicy -Name 'port-only' -Namespace 'payments' `
            -IngressRules @(
                New-IngressRule -ToPorts @(
                    New-ToPorts -Ports @(New-Port -Port '15008' -Protocol 'TCP')
                )
            )

        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -DataplaneMode 'ambient') `
            -CiliumNetworkPolicies @($policy)

        $findings = @(Test-CiliumPolicyCompatibility -Inventory $inv)

        $findings.Count | Should -Be 0
    }

    It 'emits no C-01 when the policy mixes a pod-only fromEndpoints with a waypoint-aware fromEndpoints' {
        # Author has clearly thought about waypoint identity and admitted
        # it via an additional fromEndpoints. C-01 suppresses.
        $policy = New-CiliumPolicy -Name 'mixed' -Namespace 'payments' `
            -IngressRules @(
                New-IngressRule `
                    -FromMatchLabels @{ 'app' = 'frontend' } `
                    -ToPorts @(New-ToPorts -Ports @(New-Port -Port '15008' -Protocol 'TCP'))
                New-IngressRule `
                    -FromMatchLabels @{ 'istio.io/gateway-name' = 'payments-waypoint' } `
                    -ToPorts @(New-ToPorts -Ports @(New-Port -Port '15008' -Protocol 'TCP'))
            )

        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -DataplaneMode 'ambient') `
            -CiliumNetworkPolicies @($policy)

        $findings = @(Test-CiliumPolicyCompatibility -Inventory $inv)

        ($findings | Where-Object CheckId -eq 'C-01').Count | Should -Be 0
    }
}

Describe 'Test-CiliumPolicyCompatibility (C-01 + C-02 overlap)' {

    It 'emits both C-01 and C-02 for an ambient policy that has pod-selector ingress AND no 15008 allowance' {
        # Both checks must fire on the same policy without suppressing
        # each other -- they describe distinct migration risks (port
        # reachability vs. source-identity mismatch) and an operator
        # needs both signals.
        $policy = New-CiliumPolicy -Name 'classic-l4' -Namespace 'payments' `
            -IngressRules @(
                New-IngressRule `
                    -FromMatchLabels @{ 'app' = 'frontend' } `
                    -ToPorts @(New-ToPorts -Ports @(New-Port -Port '8080' -Protocol 'TCP'))
            )

        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -DataplaneMode 'ambient') `
            -CiliumNetworkPolicies @($policy)

        $findings = @(Test-CiliumPolicyCompatibility -Inventory $inv)

        $findings.Count                                   | Should -Be 2
        ($findings | ForEach-Object CheckId | Sort-Object) | Should -Be @('C-01', 'C-02')
        ($findings | ForEach-Object Severity | Sort-Object -Unique) | Should -Be @('Blocker')
        ($findings | ForEach-Object Resource | Sort-Object -Unique) | Should -Be @(
            'CiliumNetworkPolicy/classic-l4 in namespace payments'
        )
    }
}
