#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $privateRoot = Resolve-Path "$PSScriptRoot/../../src/IstioAmbientPreflight/Private"
    . (Join-Path $privateRoot 'Format-Finding.ps1')
    . (Join-Path $privateRoot 'Test-PodLabels.ps1')

    function New-Ns {
        param(
            [string]$Name,
            [hashtable]$Labels
        )
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

    # Shape mirrors `kubectl get pods -o json` items. Labels and annotations
    # are both optional; pods often have neither, or labels but no
    # annotations (and vice versa).
    function New-Pod {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$Namespace,
            [hashtable]$Labels,
            [hashtable]$Annotations
        )
        $meta = [ordered]@{
            name      = $Name
            namespace = $Namespace
        }
        if ($PSBoundParameters.ContainsKey('Labels')) {
            $meta.labels = [pscustomobject]$Labels
        }
        if ($PSBoundParameters.ContainsKey('Annotations')) {
            $meta.annotations = [pscustomobject]$Annotations
        }
        [pscustomobject]@{
            metadata = [pscustomobject]$meta
        }
    }

    function New-Inventory {
        param(
            [object[]]$Namespaces = @(),
            [object[]]$Pods       = @()
        )
        [pscustomobject]@{
            Namespaces = @($Namespaces)
            Pods       = @($Pods)
        }
    }
}

Describe 'Test-PodLabels (P-01)' {

    It 'emits an Info finding when a pod has dataplane-mode=none in an ambient namespace' {
        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -Labels @{ 'istio.io/dataplane-mode' = 'ambient' }) `
            -Pods       @(New-Pod -Name 'legacy-tls' -Namespace 'payments' `
                            -Labels @{ 'istio.io/dataplane-mode' = 'none' })

        $findings = @(Test-PodLabels -Inventory $inv)

        $p01 = @($findings | Where-Object CheckId -eq 'P-01')
        $p01.Count       | Should -Be 1
        $p01[0].Severity | Should -Be 'Info'
        $p01[0].Category | Should -Be 'Pods'
        $p01[0].Resource | Should -Be 'Pod/legacy-tls in namespace payments'
        $p01[0].DocLink  | Should -Be 'https://istio.io/latest/docs/ambient/usage/add-workloads/'
        $p01[0].Message  | Should -Match "dataplane-mode=none"
        $p01[0].Message  | Should -Match 'bypass'
    }

    It 'emits no finding for a pod with dataplane-mode=none in a non-ambient namespace' {
        # The namespace has not been enrolled in ambient yet, so the pod
        # opt-out is not actually bypassing anything today. P-01 is
        # deliberately scoped to ambient namespaces.
        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'legacy') `
            -Pods       @(New-Pod -Name 'legacy-tls' -Namespace 'legacy' `
                            -Labels @{ 'istio.io/dataplane-mode' = 'none' })

        $findings = @(Test-PodLabels -Inventory $inv)

        ($findings | Where-Object CheckId -eq 'P-01').Count | Should -Be 0
    }

    It 'emits no finding for a pod explicitly labeled dataplane-mode=ambient in an ambient namespace' {
        # Redundant but consistent. Not an opt-out.
        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -Labels @{ 'istio.io/dataplane-mode' = 'ambient' }) `
            -Pods       @(New-Pod -Name 'api' -Namespace 'payments' `
                            -Labels @{ 'istio.io/dataplane-mode' = 'ambient' })

        $findings = @(Test-PodLabels -Inventory $inv)

        ($findings | Where-Object CheckId -eq 'P-01').Count | Should -Be 0
    }

    It 'emits no P-01 finding for a pod with no dataplane-mode label at all' {
        # P-01 only fires on explicit opt-outs. Unlabeled pods inherit
        # their namespace's ambient enrollment — nothing to flag here.
        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -Labels @{ 'istio.io/dataplane-mode' = 'ambient' }) `
            -Pods       @(New-Pod -Name 'api' -Namespace 'payments' `
                            -Labels @{ 'app' = 'api' })

        $findings = @(Test-PodLabels -Inventory $inv)

        ($findings | Where-Object CheckId -eq 'P-01').Count | Should -Be 0
    }

    It 'respects the -Namespace filter' {
        $inv = New-Inventory `
            -Namespaces @(
                New-Ns -Name 'payments' -Labels @{ 'istio.io/dataplane-mode' = 'ambient' }
                New-Ns -Name 'frontend' -Labels @{ 'istio.io/dataplane-mode' = 'ambient' }
            ) `
            -Pods @(
                New-Pod -Name 'opt-out-1' -Namespace 'payments' `
                    -Labels @{ 'istio.io/dataplane-mode' = 'none' }
                New-Pod -Name 'opt-out-2' -Namespace 'frontend' `
                    -Labels @{ 'istio.io/dataplane-mode' = 'none' }
            )

        $findings = @(Test-PodLabels -Inventory $inv -Namespace 'payments')

        $findings.Count         | Should -Be 1
        $findings[0].Resource   | Should -Be 'Pod/opt-out-1 in namespace payments'
    }
}

Describe 'Test-PodLabels (P-02)' {

    It 'emits an Info finding when a pod carries sidecar.istio.io/inject=true in an ambient namespace' {
        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -Labels @{ 'istio.io/dataplane-mode' = 'ambient' }) `
            -Pods       @(New-Pod -Name 'api' -Namespace 'payments' `
                            -Annotations @{ 'sidecar.istio.io/inject' = 'true' })

        $findings = @(Test-PodLabels -Inventory $inv)

        $p02 = @($findings | Where-Object CheckId -eq 'P-02')
        $p02.Count       | Should -Be 1
        $p02[0].Severity | Should -Be 'Info'
        $p02[0].Category | Should -Be 'Pods'
        $p02[0].Resource | Should -Be 'Pod/api in namespace payments'
        $p02[0].DocLink  | Should -Be 'https://istio.io/latest/docs/ambient/usage/add-workloads/'
        $p02[0].Message  | Should -Match 'sidecar\.istio\.io/inject'
        $p02[0].Message  | Should -Match 'no-op'
    }

    It 'emits a P-02 finding for every pod in a namespace labeled both istio-injection=enabled and ambient' {
        # This overlaps with N-02 at the namespace level, by design. P-02
        # gives the individual workload owner a finding they can act on.
        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'half-migrated' -Labels @{
                    'istio-injection'         = 'enabled'
                    'istio.io/dataplane-mode' = 'ambient'
                }) `
            -Pods @(
                New-Pod -Name 'api'     -Namespace 'half-migrated'
                New-Pod -Name 'worker'  -Namespace 'half-migrated'
            )

        $findings = @(Test-PodLabels -Inventory $inv)

        $p02 = @($findings | Where-Object CheckId -eq 'P-02')
        $p02.Count                                    | Should -Be 2
        ($p02 | ForEach-Object Resource) | Should -Contain 'Pod/api in namespace half-migrated'
        ($p02 | ForEach-Object Resource) | Should -Contain 'Pod/worker in namespace half-migrated'
        $p02[0].Message | Should -Match 'istio-injection=enabled'
    }

    It 'emits a single P-02 finding per pod even when both triggers fire at once' {
        # Pod with the inject annotation in a namespace that also carries
        # istio-injection=enabled. One pod, one finding, two reasons.
        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'half-migrated' -Labels @{
                    'istio-injection'         = 'enabled'
                    'istio.io/dataplane-mode' = 'ambient'
                }) `
            -Pods @(
                New-Pod -Name 'api' -Namespace 'half-migrated' `
                    -Annotations @{ 'sidecar.istio.io/inject' = 'true' }
            )

        $findings = @(Test-PodLabels -Inventory $inv)

        $p02 = @($findings | Where-Object CheckId -eq 'P-02')
        $p02.Count     | Should -Be 1
        $p02[0].Message | Should -Match 'sidecar\.istio\.io/inject'
        $p02[0].Message | Should -Match 'istio-injection=enabled'
    }

    It 'emits no P-02 finding when sidecar.istio.io/inject is false' {
        # An explicit "false" annotation is the documented way to opt a
        # pod out of sidecar injection — nothing stale to clean up.
        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -Labels @{ 'istio.io/dataplane-mode' = 'ambient' }) `
            -Pods       @(New-Pod -Name 'api' -Namespace 'payments' `
                            -Annotations @{ 'sidecar.istio.io/inject' = 'false' })

        $findings = @(Test-PodLabels -Inventory $inv)

        ($findings | Where-Object CheckId -eq 'P-02').Count | Should -Be 0
    }

    It 'emits no P-02 finding for a pod in a non-ambient namespace, even with the inject annotation' {
        # The pod's namespace has not been enrolled in ambient, so the
        # injection annotation is still meaningful — not stale.
        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'legacy') `
            -Pods       @(New-Pod -Name 'api' -Namespace 'legacy' `
                            -Annotations @{ 'sidecar.istio.io/inject' = 'true' })

        $findings = @(Test-PodLabels -Inventory $inv)

        ($findings | Where-Object CheckId -eq 'P-02').Count | Should -Be 0
    }

    It 'emits no finding for a clean pod in an ambient namespace' {
        # No annotations, no labels of concern, namespace cleanly ambient.
        # The expected common case; must stay silent.
        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -Labels @{ 'istio.io/dataplane-mode' = 'ambient' }) `
            -Pods       @(New-Pod -Name 'api' -Namespace 'payments' `
                            -Labels @{ 'app' = 'api' })

        $findings = @(Test-PodLabels -Inventory $inv)

        $findings.Count | Should -Be 0
    }

    It 'returns no findings when the pod list is empty' {
        $inv = New-Inventory `
            -Namespaces @(New-Ns -Name 'payments' -Labels @{ 'istio.io/dataplane-mode' = 'ambient' })

        { Test-PodLabels -Inventory $inv } | Should -Not -Throw
        @(Test-PodLabels -Inventory $inv).Count | Should -Be 0
    }
}
