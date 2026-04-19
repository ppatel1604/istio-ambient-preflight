function Test-NamespaceLabels {
    <#
    .SYNOPSIS
        N-01: Flags namespaces that are not enrolled in the ambient dataplane and
        have not explicitly opted out.

    .DESCRIPTION
        Istio Ambient mode enrolls workloads by labeling the namespace with
        istio.io/dataplane-mode=ambient. A namespace with no dataplane-mode
        label is silently excluded from the mesh after migration. Users who
        *intend* to exclude a namespace should set istio.io/dataplane-mode=none
        so the exclusion is explicit, reviewable, and survives label audits.

        This check emits one Warning finding per application namespace that has
        neither label value. System namespaces are skipped.

        CheckId:  N-01
        Category: Labels
        Severity: Warning
        Reference: https://istio.io/latest/docs/ambient/usage/add-workloads/

    .PARAMETER Inventory
        The cluster inventory returned by Get-ClusterInventory.

    .PARAMETER Namespace
        Optional filter. When supplied, only the namespace with this name is
        considered; all others are skipped.

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
        [string]$Namespace
    )

    $systemNamespaces = @(
        'kube-system'
        'kube-public'
        'kube-node-lease'
        'istio-system'
        'cilium'
    )

    $filterRequested = $PSBoundParameters.ContainsKey('Namespace') -and -not [string]::IsNullOrWhiteSpace($Namespace)

    foreach ($ns in @($Inventory.Namespaces)) {
        $name = $ns.metadata.name
        if (-not $name) { continue }
        if ($systemNamespaces -contains $name) { continue }
        if ($filterRequested -and $name -ne $Namespace) { continue }

        $labels = $null
        if ($ns.metadata.PSObject.Properties.Name -contains 'labels') {
            $labels = $ns.metadata.labels
        }

        $mode = $null
        if ($labels) {
            $modeProp = $labels.PSObject.Properties['istio.io/dataplane-mode']
            if ($modeProp) { $mode = $modeProp.Value }
        }

        if ($mode -eq 'ambient' -or $mode -eq 'none') { continue }

        $message = @(
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
            -Message  $message `
            -DocLink  'https://istio.io/latest/docs/ambient/usage/add-workloads/'
    }
}
