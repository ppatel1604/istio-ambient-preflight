function Test-CiliumPolicyCompatibility {
    <#
    .SYNOPSIS
        Cilium NetworkPolicy compatibility checks for ambient migration.

    .DESCRIPTION
        Runs every CiliumNetworkPolicy-level check in a single pass over the
        inventory. Today this covers:

          - C-01 (Blocker, Network):
              Ambient-mode pod-to-pod traffic is sourced from the waypoint
              proxy's identity, not the original client pod. A
              CiliumNetworkPolicy whose ingress rules restrict source by
              pod-selector matchLabels (e.g. 'app=frontend') will silently
              drop waypoint-routed traffic after migration -- the policy
              was authored against pre-ambient identities and still parses
              cleanly, so the failure mode is invisible. C-01 fires when a
              policy in an ambient namespace has at least one
              'fromEndpoints' rule with a non-empty matchLabels that does
              NOT mention any waypoint-identity label
              ('istio.io/gateway-name' or 'istio.io/waypoint-for'). If any
              fromEndpoints anywhere in the policy already references one
              of those labels, the operator has clearly thought about
              waypoints and the finding is suppressed.

          - C-02 (Blocker, Network):
              In ambient mode, mesh traffic for a pod is terminated on the
              destination node by ztunnel, which receives tunneled traffic
              over HBONE on TCP/15008 before handing it off to the workload.
              A CiliumNetworkPolicy in an ambient-labeled namespace that
              declares ingress rules without allowing TCP/15008 will
              silently drop mesh traffic after migration. A policy is
              compliant when it has no ingress section (no ingress
              restriction at all), or when at least one ingress rule
              explicitly admits TCP/15008 (or covers 15008 via a port range).

        Policies in non-ambient namespaces are skipped: they are not yet
        affected by the migration. The function emits zero findings (and
        no error) when CiliumNetworkPolicies is empty -- the typical case
        for clusters that do not have the Cilium CRDs installed.

        References:
          - https://istio.io/latest/docs/ambient/usage/waypoint/
          - https://istio.io/latest/docs/ambient/architecture/traffic-redirection/

    .PARAMETER Inventory
        The cluster inventory returned by Get-ClusterInventory.

    .OUTPUTS
        Zero or more finding objects produced by Format-Finding.
    #>
    [CmdletBinding()]
    [OutputType('IstioAmbientPreflight.Finding')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Inventory
    )

    # Build the set of ambient-enrolled namespaces from the inventory. A
    # HashSet makes per-policy lookup O(1) and makes the intent explicit.
    $ambientNamespaces = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($ns in @($Inventory.Namespaces)) {
        $name = $ns.metadata.name
        if (-not $name) { continue }

        $labels = $null
        if ($ns.metadata.PSObject.Properties.Name -contains 'labels') {
            $labels = $ns.metadata.labels
        }
        if (-not $labels) { continue }

        $modeProp = $labels.PSObject.Properties['istio.io/dataplane-mode']
        if (-not $modeProp) { continue }

        if ($modeProp.Value -eq 'ambient') {
            [void]$ambientNamespaces.Add($name)
        }
    }

    foreach ($policy in @($Inventory.CiliumNetworkPolicies)) {
        $policyName = $policy.metadata.name
        $policyNs   = $policy.metadata.namespace
        if (-not $policyName -or -not $policyNs) { continue }
        if (-not $ambientNamespaces.Contains($policyNs)) { continue }

        $ingress = $null
        if ($policy.PSObject.Properties.Name -contains 'spec' -and $policy.spec -and
            $policy.spec.PSObject.Properties.Name -contains 'ingress') {
            $ingress = $policy.spec.ingress
        }

        # No ingress section (or an empty one) means the policy does not
        # restrict ingress; ztunnel traffic flows through unchallenged and
        # there is no source-selector to mismatch the waypoint either.
        # Note: @($null) has Count 1 in PowerShell, so guard on $null first.
        if (-not $ingress) { continue }
        $ingressRules = @($ingress)
        if ($ingressRules.Count -eq 0) { continue }

        # ---- C-02: ztunnel HBONE TCP/15008 must be reachable ----
        $allows15008 = $false
        foreach ($rule in $ingressRules) {
            if (-not $rule) { continue }

            $toPorts = $null
            if ($rule.PSObject.Properties.Name -contains 'toPorts') {
                $toPorts = $rule.toPorts
            }

            # A rule with no toPorts permits any port on this ingress selector.
            $toPortsArr = @($toPorts)
            if ($toPortsArr.Count -eq 0) { $allows15008 = $true; break }

            foreach ($toPort in $toPortsArr) {
                if (-not $toPort) { continue }

                $ports = $null
                if ($toPort.PSObject.Properties.Name -contains 'ports') {
                    $ports = $toPort.ports
                }

                foreach ($p in @($ports)) {
                    if (-not $p) { continue }

                    $protocol = 'TCP'
                    if ($p.PSObject.Properties.Name -contains 'protocol' -and $p.protocol) {
                        $protocol = [string]$p.protocol
                    }
                    if ($protocol -ne 'TCP' -and $protocol -ne 'ANY') { continue }

                    $portVal = $null
                    if ($p.PSObject.Properties.Name -contains 'port') {
                        $portVal = [string]$p.port
                    }
                    if (-not $portVal) { continue }

                    $endPortVal = $null
                    if ($p.PSObject.Properties.Name -contains 'endPort' -and $p.endPort) {
                        $endPortVal = [int]$p.endPort
                    }

                    if ($endPortVal) {
                        $startInt = 0
                        if ([int]::TryParse($portVal, [ref]$startInt)) {
                            if (15008 -ge $startInt -and 15008 -le $endPortVal) {
                                $allows15008 = $true; break
                            }
                        }
                    } elseif ($portVal -eq '15008') {
                        $allows15008 = $true; break
                    }
                }

                if ($allows15008) { break }
            }

            if ($allows15008) { break }
        }

        if (-not $allows15008) {
            $c02Message = @(
                "CiliumNetworkPolicy '$policyName' in ambient namespace '$policyNs' declares ingress rules"
                "but does not allow TCP port 15008. In ambient mode, mesh traffic arrives on the destination"
                "node via ztunnel using HBONE on TCP/15008; this policy will silently drop mesh traffic after"
                "migration. Add an ingress rule that permits TCP/15008 from the ztunnel DaemonSet (for example,"
                "select 'k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=istio-system' with"
                "toPorts port 15008), or migrate the L7 controls to an Istio AuthorizationPolicy."
            ) -join ' '

            Format-Finding `
                -Severity 'Blocker' `
                -Category 'Network' `
                -CheckId  'C-02' `
                -Resource "CiliumNetworkPolicy/$policyName in namespace $policyNs" `
                -Message  $c02Message `
                -DocLink  'https://istio.io/latest/docs/ambient/architecture/traffic-redirection/'
        }

        # ---- C-01: fromEndpoints pod-selector must account for waypoint identity ----
        # Walk every fromEndpoints across every ingress rule once. Track
        # whether the policy author has already considered waypoint
        # identity (any matchLabels referencing istio.io/gateway-name or
        # istio.io/waypoint-for) and whether at least one fromEndpoints
        # restricts to specific pod labels that lack those keys.
        $hasWaypointSelector = $false
        $hasPodOnlySelector  = $false
        foreach ($rule in $ingressRules) {
            if (-not $rule) { continue }

            $fromEndpoints = $null
            if ($rule.PSObject.Properties.Name -contains 'fromEndpoints') {
                $fromEndpoints = $rule.fromEndpoints
            }
            foreach ($from in @($fromEndpoints)) {
                if (-not $from) { continue }

                $matchLabels = $null
                if ($from.PSObject.Properties.Name -contains 'matchLabels') {
                    $matchLabels = $from.matchLabels
                }
                if (-not $matchLabels) { continue }

                # An empty matchLabels object means "any endpoint" (no
                # restriction beyond the rule itself); waypoint traffic
                # matches it implicitly, so it counts as neither a
                # waypoint-aware selector nor a pod-only selector.
                # Note: @($matchLabels.PSObject.Properties.Name).Count is
                # 1 (not 0) when there are no properties, because
                # @($null) wraps to a single-element array. Count the
                # Properties collection directly instead.
                $properties = @($matchLabels.PSObject.Properties)
                if ($properties.Count -eq 0) { continue }
                $labelKeys = @($properties | ForEach-Object Name)

                $rulePicksWaypoint =
                    ($labelKeys -contains 'istio.io/gateway-name') -or
                    ($labelKeys -contains 'istio.io/waypoint-for')

                if ($rulePicksWaypoint) {
                    $hasWaypointSelector = $true
                } else {
                    $hasPodOnlySelector = $true
                }
            }
        }

        if ($hasPodOnlySelector -and -not $hasWaypointSelector) {
            $c01Message = @(
                "CiliumNetworkPolicy '$policyName' in ambient namespace '$policyNs' restricts ingress by"
                "pod-selector matchLabels (for example, allowing only sources like 'app=frontend'). In"
                "ambient mode with a waypoint proxy, mesh traffic arrives at the destination from the"
                "waypoint pod's identity rather than the original client; the original pod labels are no"
                "longer present on the connection, so this policy will silently drop waypoint-routed traffic"
                "after migration. Either add a fromEndpoints rule that admits the waypoint via its"
                "'istio.io/gateway-name' label, or migrate L7 source-identity controls to an Istio"
                "AuthorizationPolicy (which evaluates against the original peer identity)."
            ) -join ' '

            Format-Finding `
                -Severity 'Blocker' `
                -Category 'Network' `
                -CheckId  'C-01' `
                -Resource "CiliumNetworkPolicy/$policyName in namespace $policyNs" `
                -Message  $c01Message `
                -DocLink  'https://istio.io/latest/docs/ambient/usage/waypoint/'
        }
    }
}
