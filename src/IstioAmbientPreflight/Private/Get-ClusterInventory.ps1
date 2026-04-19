function Get-ClusterInventory {
    <#
    .SYNOPSIS
        Reads the cluster once and returns a structured inventory of the resource
        types that ambient-compatibility checks care about.

    .DESCRIPTION
        Single-pass collector. Every check in this module consumes the object
        returned here rather than re-querying the cluster, so a full preflight run
        makes at most one kubectl call per resource type.

        Resource types queried:
            Namespaces             - core/v1 (cluster-scoped)
            Pods                   - core/v1
            IstioGateways          - gateway.networking.istio.io
            VirtualServices        - networking.istio.io
            DestinationRules       - networking.istio.io
            CiliumNetworkPolicies  - cilium.io
            GatewayAPIGateways     - gateway.networking.k8s.io

        Optional components (Istio, Cilium, Gateway API) may not be installed on
        a given cluster. When the API server reports that a resource type is
        unknown, the corresponding field is returned as an empty array and a
        verbose message is emitted. Any other kubectl error is rethrown.

    .PARAMETER Context
        Name of the kubectl context to target. When omitted, kubectl uses the
        current-context from kubeconfig.

    .EXAMPLE
        PS> $inv = Get-ClusterInventory -Context my-cluster
        PS> $inv.Namespaces.Count
        14

    .OUTPUTS
        PSCustomObject with Context plus the seven resource-list properties
        listed above, each an array of kubectl JSON objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Context
    )

    $useContext = $PSBoundParameters.ContainsKey('Context') -and -not [string]::IsNullOrWhiteSpace($Context)

    $resourceMap = [ordered]@{
        Namespaces            = @{ Resource = 'namespaces';                           ClusterScoped = $true  }
        Pods                  = @{ Resource = 'pods';                                 ClusterScoped = $false }
        IstioGateways         = @{ Resource = 'gateways.gateway.networking.istio.io'; ClusterScoped = $false }
        VirtualServices       = @{ Resource = 'virtualservices.networking.istio.io';  ClusterScoped = $false }
        DestinationRules      = @{ Resource = 'destinationrules.networking.istio.io'; ClusterScoped = $false }
        CiliumNetworkPolicies = @{ Resource = 'ciliumnetworkpolicies.cilium.io';      ClusterScoped = $false }
        GatewayAPIGateways    = @{ Resource = 'gateways.gateway.networking.k8s.io';   ClusterScoped = $false }
    }

    $inventory = [ordered]@{
        Context = if ($useContext) { $Context } else { $null }
    }

    # Messages kubectl emits when a resource kind is unknown to the API server.
    # Matching on substrings keeps this resilient to small phrasing changes
    # across kubectl versions.
    $crdMissingPatterns = @(
        "doesn't have a resource type",
        'the server could not find the requested resource',
        'the server doesn''t have a resource'
    )

    foreach ($name in $resourceMap.Keys) {
        $resourceType  = $resourceMap[$name].Resource
        $clusterScoped = $resourceMap[$name].ClusterScoped

        $kubectlArgs = @('get', $resourceType, '-o', 'json')
        if (-not $clusterScoped) {
            $kubectlArgs = @('get', $resourceType, '--all-namespaces', '-o', 'json')
        }

        $invokeParams = @{ Arguments = $kubectlArgs }
        if ($useContext) { $invokeParams.Context = $Context }

        try {
            $response = Invoke-Kubectl @invokeParams

            $items = @()
            if ($response -and $response.PSObject.Properties.Name -contains 'items' -and $null -ne $response.items) {
                $items = @($response.items)
            }
            $inventory[$name] = $items
        } catch {
            $msg = $_.Exception.Message
            $isCrdMissing = $false
            foreach ($pattern in $crdMissingPatterns) {
                if ($msg -like "*$pattern*") { $isCrdMissing = $true; break }
            }

            if ($isCrdMissing) {
                Write-Verbose "[$name] Resource type '$resourceType' not installed in cluster; treating as empty."
                $inventory[$name] = @()
            } else {
                throw
            }
        }
    }

    return [pscustomobject]$inventory
}
