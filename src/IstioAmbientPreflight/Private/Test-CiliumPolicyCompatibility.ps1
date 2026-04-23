function Test-CiliumPolicyCompatibility {
    <#
    .SYNOPSIS
        C-02: Flags CiliumNetworkPolicies in ambient-enrolled namespaces whose
        ingress rules do not admit ztunnel HBONE traffic on TCP port 15008.

    .DESCRIPTION
        In Istio Ambient mode, mesh traffic for a pod is terminated on the
        destination node by ztunnel, which receives tunneled traffic over HBONE
        on TCP port 15008 before handing it off to the workload. A Cilium
        NetworkPolicy in an ambient-labeled namespace that declares ingress
        rules without allowing TCP/15008 will silently drop mesh traffic after
        migration: the policy looks correct for direct pod-to-pod calls, but
        the actual packets now arrive from ztunnel on port 15008.

        A policy is considered compliant when it has no ingress section or an
        empty one (the policy does not restrict ingress, so ztunnel is
        implicitly permitted), OR when at least one ingress rule allows TCP
        port 15008. An ingress rule allows TCP/15008 when either:
          - it has no toPorts (any port is allowed on that rule), or
          - it has a toPorts entry whose protocol is TCP or unspecified and
            whose port is 15008, or whose [port, endPort] range covers 15008.

        Policies outside ambient-labeled namespaces are skipped: they are not
        yet affected by the migration.

        CheckId:  C-02
        Category: Network
        Severity: Blocker
        Reference: https://istio.io/latest/docs/ambient/architecture/traffic-redirection/

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
        # restrict ingress; ztunnel traffic flows through unchallenged.
        # Note: @($null) has Count 1 in PowerShell, so guard on $null first.
        if (-not $ingress) { continue }
        $ingressRules = @($ingress)
        if ($ingressRules.Count -eq 0) { continue }

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

        if ($allows15008) { continue }

        $message = @(
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
            -Message  $message `
            -DocLink  'https://istio.io/latest/docs/ambient/architecture/traffic-redirection/'
    }
}
