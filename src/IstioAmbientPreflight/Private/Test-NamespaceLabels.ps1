function Test-NamespaceLabels {
    <#
    .SYNOPSIS
        Namespace-label checks for ambient readiness.

    .DESCRIPTION
        Runs every namespace-label check in a single pass over the inventory.
        Today this covers:

          - N-01 (Warning, Labels):
              Flags namespaces with no istio.io/dataplane-mode label. After
              migration such namespaces are silently excluded from the mesh.
              Namespaces that have explicitly opted out with
              istio.io/dataplane-mode=none are considered compliant.

          - N-02 (Blocker, Labels):
              Flags namespaces that are simultaneously enrolled in sidecar
              injection (istio-injection=enabled) and the ambient dataplane
              (istio.io/dataplane-mode=ambient). Istio's documented practice
              is one mode per namespace; the mixed state typically indicates
              an incomplete migration and produces ambiguous behavior for
              workloads scheduled into the namespace.

        System namespaces (kube-system, kube-public, kube-node-lease,
        istio-system, cilium) are skipped, as are any names supplied via
        -ExcludeNamespace.

        Reference: https://istio.io/latest/docs/ambient/usage/add-workloads/

    .PARAMETER Inventory
        The cluster inventory returned by Get-ClusterInventory.

    .PARAMETER Namespace
        Optional filter. When supplied, only the namespace with this name is
        considered; all others are skipped.

    .PARAMETER ExcludeNamespace
        Additional namespace names to skip, appended to the built-in system
        namespace list. Useful for suppressing expected noise from the
        report (for example, infrastructure namespaces the user has
        decided to leave outside the mesh).

    .OUTPUTS
        Zero or more finding objects produced by Format-Finding.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'The check inspects the overall label set on each namespace; "Labels" reflects that collective concern.')]
    [OutputType('IstioAmbientPreflight.Finding')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Inventory,

        [Parameter()]
        [string]$Namespace,

        [Parameter()]
        [string[]]$ExcludeNamespace
    )

    $systemNamespaces = @(
        'kube-system'
        'kube-public'
        'kube-node-lease'
        'istio-system'
        'cilium'
    )

    $skipList = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($sysNs in $systemNamespaces) { [void]$skipList.Add($sysNs) }
    if ($ExcludeNamespace) {
        foreach ($extra in $ExcludeNamespace) {
            if (-not [string]::IsNullOrWhiteSpace($extra)) { [void]$skipList.Add($extra) }
        }
    }

    $filterRequested = $PSBoundParameters.ContainsKey('Namespace') -and -not [string]::IsNullOrWhiteSpace($Namespace)

    foreach ($ns in @($Inventory.Namespaces)) {
        $name = $ns.metadata.name
        if (-not $name) { continue }
        if ($skipList.Contains($name)) { continue }
        if ($filterRequested -and $name -ne $Namespace) { continue }

        $labels = $null
        if ($ns.metadata.PSObject.Properties.Name -contains 'labels') {
            $labels = $ns.metadata.labels
        }

        $mode = $null
        $injection = $null
        if ($labels) {
            $modeProp = $labels.PSObject.Properties['istio.io/dataplane-mode']
            if ($modeProp) { $mode = $modeProp.Value }

            $injectionProp = $labels.PSObject.Properties['istio-injection']
            if ($injectionProp) { $injection = $injectionProp.Value }
        }

        # N-02: conflicting labels. Check before N-01 -- a namespace that has
        # both labels is in the ambient set, so N-01 would not fire anyway,
        # but the ordering also documents that the Blocker case is the one
        # that preempts the Warning.
        if ($mode -eq 'ambient' -and $injection -eq 'enabled') {
            $n02Message = @(
                "Namespace '$name' is labeled for BOTH sidecar injection (istio-injection=enabled)"
                "and the ambient dataplane (istio.io/dataplane-mode=ambient)."
                "Istio's documented practice is one mode per namespace; mixed labels produce"
                "ambiguous behavior and typically indicate an incomplete migration."
                "Remove the 'istio-injection' label"
                "('kubectl label namespace $name istio-injection-') before enabling ambient"
                "on production workloads."
            ) -join ' '

            Format-Finding `
                -Severity 'Blocker' `
                -Category 'Labels' `
                -CheckId  'N-02' `
                -Resource "Namespace/$name" `
                -Message  $n02Message `
                -DocLink  'https://istio.io/latest/docs/ambient/usage/add-workloads/'

            continue
        }

        # N-01: missing or non-explicit dataplane-mode.
        if ($mode -eq 'ambient' -or $mode -eq 'none') { continue }

        $n01Message = @(
            "Namespace '$name' has no 'istio.io/dataplane-mode' label."
            "Workloads here will not be enrolled in the ambient mesh after migration."
            "Apply 'kubectl label namespace $name istio.io/dataplane-mode=ambient' to enroll,"
            "or 'kubectl label namespace $name istio.io/dataplane-mode=none' to explicitly opt out."
        ) -join ' '

        Format-Finding `
            -Severity 'Warning' `
            -Category 'Labels' `
            -CheckId  'N-01' `
            -Resource "Namespace/$name" `
            -Message  $n01Message `
            -DocLink  'https://istio.io/latest/docs/ambient/usage/add-workloads/'
    }
}
