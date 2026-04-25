function Test-PodLabels {
    <#
    .SYNOPSIS
        Pod-label checks for ambient readiness.

    .DESCRIPTION
        Runs every pod-level label/annotation check in a single pass over the
        inventory. Today this covers:

          - P-01 (Info, Pods):
              Surfaces pods that have 'istio.io/dataplane-mode=none' inside a
              namespace labeled 'istio.io/dataplane-mode=ambient'. Such pods
              are explicitly excluded from the ambient mesh even when the
              namespace is enrolled. This is a legitimate pattern (workloads
              that manage their own TLS or networking), but surfacing it
              during migration planning ensures the exclusion is intentional
              rather than a forgotten leftover.

          - P-02 (Info, Pods):
              Surfaces pods in ambient-labeled namespaces that still carry
              sidecar-injection configuration. Two triggers are considered:
                * The pod carries the 'sidecar.istio.io/inject=true'
                  annotation.
                * The pod's namespace is simultaneously labeled
                  'istio-injection=enabled' and
                  'istio.io/dataplane-mode=ambient' (the N-02 condition
                  surfaced at the pod level -- each workload owner benefits
                  from seeing their pod listed individually).
              In ambient mode the sidecar-injection directive is a no-op.
              The pod still runs, but the stale label/annotation misleads
              future operators into thinking sidecars are in play. P-02
              recommends cleanup.

        P-02 may fire on the same namespace that already triggered N-02.
        That is deliberate: N-02 is for the platform team (fix the
        namespace); P-02 is for the workload owner (clean up my pod).

        Reference: https://istio.io/latest/docs/ambient/usage/add-workloads/

    .PARAMETER Inventory
        The cluster inventory returned by Get-ClusterInventory.

    .PARAMETER Namespace
        Optional filter. When supplied, only pods in this namespace are
        considered; all others are skipped.

    .OUTPUTS
        Zero or more finding objects produced by Format-Finding.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'The check inspects the overall label/annotation set on each pod; "Labels" reflects that collective concern.')]
    [OutputType('IstioAmbientPreflight.Finding')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Inventory,

        [Parameter()]
        [string]$Namespace
    )

    # Build a map of namespace name -> labels-object for O(1) lookup during
    # the pod loop. Ambient mode is a namespace-level enrollment, so every
    # pod check first needs its namespace's label context.
    $nsLabelMap = @{}
    foreach ($ns in @($Inventory.Namespaces)) {
        $nsName = $ns.metadata.name
        if (-not $nsName) { continue }
        $labels = $null
        if ($ns.metadata.PSObject.Properties.Name -contains 'labels') {
            $labels = $ns.metadata.labels
        }
        $nsLabelMap[$nsName] = $labels
    }

    $filterRequested = $PSBoundParameters.ContainsKey('Namespace') -and -not [string]::IsNullOrWhiteSpace($Namespace)

    foreach ($pod in @($Inventory.Pods)) {
        $podName = $pod.metadata.name
        $podNs   = $pod.metadata.namespace
        if (-not $podName -or -not $podNs) { continue }
        if ($filterRequested -and $podNs -ne $Namespace) { continue }

        # Resolve the pod's namespace labels. Pods in unknown namespaces
        # (inventory drift) are skipped rather than flagged.
        if (-not $nsLabelMap.ContainsKey($podNs)) { continue }
        $nsLabels = $nsLabelMap[$podNs]

        $nsMode      = $null
        $nsInjection = $null
        if ($nsLabels) {
            $modeProp = $nsLabels.PSObject.Properties['istio.io/dataplane-mode']
            if ($modeProp) { $nsMode = $modeProp.Value }
            $injProp  = $nsLabels.PSObject.Properties['istio-injection']
            if ($injProp)  { $nsInjection = $injProp.Value }
        }

        # Both P-01 and P-02 only concern ambient-enrolled namespaces.
        # Non-ambient namespaces are outside the migration front and
        # produce no pod-level findings.
        if ($nsMode -ne 'ambient') { continue }

        # Resolve pod labels and annotations once.
        $podLabels      = $null
        $podAnnotations = $null
        if ($pod.metadata.PSObject.Properties.Name -contains 'labels') {
            $podLabels = $pod.metadata.labels
        }
        if ($pod.metadata.PSObject.Properties.Name -contains 'annotations') {
            $podAnnotations = $pod.metadata.annotations
        }

        # P-01: explicit opt-out via pod-level dataplane-mode=none.
        $podMode = $null
        if ($podLabels) {
            $modeProp = $podLabels.PSObject.Properties['istio.io/dataplane-mode']
            if ($modeProp) { $podMode = $modeProp.Value }
        }

        if ($podMode -eq 'none') {
            $p01Message = @(
                "Pod '$podName' in namespace '$podNs' is labeled"
                "'istio.io/dataplane-mode=none', explicitly opting out of the"
                "ambient mesh even though the namespace is enrolled as ambient."
                "The pod will bypass ztunnel, L4 authorization, and mesh telemetry."
                "This is fine if intentional (for example, a workload that manages"
                "its own TLS or networking); otherwise remove the pod label so the"
                "pod joins the namespace's ambient enrollment."
            ) -join ' '

            Format-Finding `
                -Severity 'Info' `
                -Category 'Pods' `
                -CheckId  'P-01' `
                -Resource "Pod/$podName in namespace $podNs" `
                -Message  $p01Message `
                -DocLink  'https://istio.io/latest/docs/ambient/usage/add-workloads/'
        }

        # P-02: stale sidecar-injection configuration on an ambient-enrolled pod.
        $hasInjectAnnotation = $false
        if ($podAnnotations) {
            $injAnn = $podAnnotations.PSObject.Properties['sidecar.istio.io/inject']
            if ($injAnn -and [string]$injAnn.Value -eq 'true') {
                $hasInjectAnnotation = $true
            }
        }

        $hasConflictingNsLabel = ($nsInjection -eq 'enabled')

        if ($hasInjectAnnotation -or $hasConflictingNsLabel) {
            $reasons = [System.Collections.Generic.List[string]]::new()
            if ($hasInjectAnnotation) {
                [void]$reasons.Add("pod annotation 'sidecar.istio.io/inject=true'")
            }
            if ($hasConflictingNsLabel) {
                [void]$reasons.Add("namespace label 'istio-injection=enabled'")
            }

            $p02Message = @(
                "Pod '$podName' in ambient namespace '$podNs' carries stale sidecar-injection"
                "configuration ($($reasons -join ' and ')). In ambient mode the injection"
                "directive is a no-op -- the pod runs but no sidecar is added. The stale"
                "directive misleads future operators into believing this workload is on"
                "the sidecar dataplane. Remove the label/annotation to reflect the"
                "pod's actual ambient enrollment."
            ) -join ' '

            Format-Finding `
                -Severity 'Info' `
                -Category 'Pods' `
                -CheckId  'P-02' `
                -Resource "Pod/$podName in namespace $podNs" `
                -Message  $p02Message `
                -DocLink  'https://istio.io/latest/docs/ambient/usage/add-workloads/'
        }
    }
}
