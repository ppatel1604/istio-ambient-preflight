function Test-GatewayConflict {
    <#
    .SYNOPSIS
        Ingress checks: Istio Gateway vs. Gateway API overlap, and dangling
        VirtualService gateway references.

    .DESCRIPTION
        Runs every ingress-level check in a single pass over the inventory.
        Today this covers:

          - G-01 (Blocker, Ingress):
              Flags each pair of an Istio Gateway (networking.istio.io) and a
              Gateway API Gateway (gateway.networking.k8s.io) that claim
              overlapping hostnames. The two APIs are programmed into
              separate gateway deployments, so a hostname claimed by both has
              two independent entry points; which one actually serves traffic
              depends on DNS and load-balancer wiring outside the mesh. This
              is the typical half-migrated state between the classic Istio
              API and the Gateway API, which Istio recommends for ambient.

              Hostname matching follows both APIs' documented semantics:
                * Istio 'servers[].hosts' entries may carry a 'namespace/'
                  prefix ('./', '*/', 'ns/'); only the host part is compared.
                  '*' matches every host.
                * A Gateway API listener with no 'hostname' matches every
                  host.
                * '*.example.com' matches any host ending in '.example.com'.

              Gateway API Gateways that are mesh infrastructure rather than
              ingress (gatewayClassName 'istio-waypoint' or 'istio-east-west',
              and listeners with protocol 'HBONE') are ignored; they carry no
              hostname and would otherwise look like catch-all ingress.

          - G-02 (Warning, Ingress):
              Flags VirtualServices that bind to an Istio Gateway which does
              not exist. References are read from 'spec.gateways' and from
              'spec.http[].match[].gateways'. The reserved name 'mesh' is
              skipped. Per the VirtualService reference, an unqualified name
              resolves in the VirtualService's own namespace and
              '<namespace>/<name>' resolves explicitly. The legacy
              '<name>.<namespace>[.svc.cluster.local]' form is tried as a
              fallback before flagging. When a Gateway API Gateway with the
              referenced name exists, the message points out that a
              VirtualService cannot bind to it.

        Both checks emit zero findings (and no error) when the Istio or
        Gateway API CRDs are not installed.

        References:
          - https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/
          - https://istio.io/latest/docs/reference/config/networking/gateway/
          - https://istio.io/latest/docs/reference/config/networking/virtual-service/
          - https://gateway-api.sigs.k8s.io/reference/spec/#listener

    .PARAMETER Inventory
        The cluster inventory returned by Get-ClusterInventory.

    .PARAMETER Namespace
        Optional filter. G-01 reports a pair when either gateway lives in
        this namespace; G-02 considers only VirtualServices in this
        namespace.

    .OUTPUTS
        Zero or more finding objects produced by Format-Finding.
    #>
    [CmdletBinding()]
    [OutputType('IstioAmbientPreflight.Finding')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Inventory,

        [Parameter()]
        [string]$Namespace
    )

    $filterRequested = $PSBoundParameters.ContainsKey('Namespace') -and -not [string]::IsNullOrWhiteSpace($Namespace)

    # Safe property read for kubectl JSON objects under StrictMode.
    function Get-Prop {
        param($Object, [string]$Name)
        if ($null -eq $Object) { return $null }
        $prop = $Object.PSObject.Properties[$Name]
        if ($prop) { return $prop.Value }
        return $null
    }

    # True when two hostname patterns can match at least one common host.
    function Test-HostOverlap {
        param([string]$A, [string]$B)
        if ($A -eq '*' -or $B -eq '*') { return $true }
        if ($A -eq $B) { return $true }

        $aWild = $A.StartsWith('*.')
        $bWild = $B.StartsWith('*.')
        if ($aWild -and $bWild) {
            $aSuffix = $A.Substring(1)
            $bSuffix = $B.Substring(1)
            return $aSuffix.EndsWith($bSuffix) -or $bSuffix.EndsWith($aSuffix)
        }
        if ($aWild) { return $B.EndsWith($A.Substring(1)) }
        if ($bWild) { return $A.EndsWith($B.Substring(1)) }
        return $false
    }

    $istioGateways = @((Get-Prop $Inventory 'IstioGateways') | Where-Object { $_ })
    $gwApiGateways = @((Get-Prop $Inventory 'GatewayAPIGateways') | Where-Object { $_ })

    # ---- G-01: Istio Gateway and Gateway API Gateway claiming the same host ----
    $istioHostSets = foreach ($gw in $istioGateways) {
        $meta = Get-Prop $gw 'metadata'
        $name = Get-Prop $meta 'name'
        $ns   = Get-Prop $meta 'namespace'
        if (-not $name -or -not $ns) { continue }

        $hosts = [System.Collections.Generic.List[string]]::new()
        foreach ($server in @(Get-Prop (Get-Prop $gw 'spec') 'servers')) {
            foreach ($h in @(Get-Prop $server 'hosts')) {
                if ([string]::IsNullOrWhiteSpace($h)) { continue }
                $hostPart = ([string]$h).ToLowerInvariant()
                $slash = $hostPart.IndexOf('/')
                if ($slash -ge 0) { $hostPart = $hostPart.Substring($slash + 1) }
                if ($hostPart -and -not $hosts.Contains($hostPart)) { $hosts.Add($hostPart) }
            }
        }
        if ($hosts.Count -eq 0) { continue }
        [pscustomobject]@{ Name = $name; Namespace = $ns; Hosts = $hosts }
    }

    $meshInfraClasses = @('istio-waypoint', 'istio-east-west')
    $gwApiHostSets = foreach ($gw in $gwApiGateways) {
        $meta = Get-Prop $gw 'metadata'
        $name = Get-Prop $meta 'name'
        $ns   = Get-Prop $meta 'namespace'
        if (-not $name -or -not $ns) { continue }

        $spec = Get-Prop $gw 'spec'
        if ($meshInfraClasses -contains (Get-Prop $spec 'gatewayClassName')) { continue }

        $hosts = [System.Collections.Generic.List[string]]::new()
        foreach ($listener in @(Get-Prop $spec 'listeners')) {
            if (-not $listener) { continue }
            if ((Get-Prop $listener 'protocol') -eq 'HBONE') { continue }
            $hostname = Get-Prop $listener 'hostname'
            $hostPart = if ([string]::IsNullOrWhiteSpace($hostname)) { '*' } else { ([string]$hostname).ToLowerInvariant() }
            if (-not $hosts.Contains($hostPart)) { $hosts.Add($hostPart) }
        }
        if ($hosts.Count -eq 0) { continue }
        [pscustomobject]@{ Name = $name; Namespace = $ns; Hosts = $hosts }
    }

    foreach ($istio in @($istioHostSets)) {
        foreach ($gwApi in @($gwApiHostSets)) {
            if ($filterRequested -and $istio.Namespace -ne $Namespace -and $gwApi.Namespace -ne $Namespace) { continue }

            $overlaps = [System.Collections.Generic.List[string]]::new()
            foreach ($a in $istio.Hosts) {
                foreach ($b in $gwApi.Hosts) {
                    if (Test-HostOverlap -A $a -B $b) {
                        $pair = if ($a -eq $b) { "'$a'" } else { "'$a' (Istio) vs '$b' (Gateway API)" }
                        if (-not $overlaps.Contains($pair)) { $overlaps.Add($pair) }
                    }
                }
            }
            if ($overlaps.Count -eq 0) { continue }

            $g01Message = @(
                "Istio Gateway '$($istio.Namespace)/$($istio.Name)' and Gateway API Gateway"
                "'$($gwApi.Namespace)/$($gwApi.Name)' both claim overlapping hostnames: $($overlaps -join ', ')."
                "The two APIs are served by separate gateway deployments, so these hosts have two independent"
                "entry points and which one receives traffic depends on DNS and load-balancer wiring outside"
                "the mesh. Routes and policies attached to one gateway do not apply to the other. Move each"
                "hostname to a single API (Istio recommends the Gateway API for ambient) and remove it from"
                "the other gateway before migrating."
            ) -join ' '

            Format-Finding `
                -Severity 'Blocker' `
                -Category 'Ingress' `
                -CheckId  'G-01' `
                -Resource "Gateway/$($istio.Name) in namespace $($istio.Namespace) (Istio) + Gateway/$($gwApi.Name) in namespace $($gwApi.Namespace) (Gateway API)" `
                -Message  $g01Message `
                -DocLink  'https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/'
        }
    }

    # ---- G-02: VirtualServices bound to Istio Gateways that don't exist ----
    $istioKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($gw in $istioGateways) {
        $meta = Get-Prop $gw 'metadata'
        $name = Get-Prop $meta 'name'
        $ns   = Get-Prop $meta 'namespace'
        if ($name -and $ns) { [void]$istioKeys.Add("$ns/$name") }
    }
    $gwApiKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($gw in $gwApiGateways) {
        $meta = Get-Prop $gw 'metadata'
        $name = Get-Prop $meta 'name'
        $ns   = Get-Prop $meta 'namespace'
        if ($name -and $ns) { [void]$gwApiKeys.Add("$ns/$name") }
    }

    foreach ($vs in @(Get-Prop $Inventory 'VirtualServices')) {
        $meta   = Get-Prop $vs 'metadata'
        $vsName = Get-Prop $meta 'name'
        $vsNs   = Get-Prop $meta 'namespace'
        if (-not $vsName -or -not $vsNs) { continue }
        if ($filterRequested -and $vsNs -ne $Namespace) { continue }

        $spec = Get-Prop $vs 'spec'
        $refs = [System.Collections.Generic.List[string]]::new()
        foreach ($r in @(Get-Prop $spec 'gateways')) {
            if ($r -and -not $refs.Contains([string]$r)) { $refs.Add([string]$r) }
        }
        foreach ($route in @(Get-Prop $spec 'http')) {
            foreach ($match in @(Get-Prop $route 'match')) {
                foreach ($r in @(Get-Prop $match 'gateways')) {
                    if ($r -and -not $refs.Contains([string]$r)) { $refs.Add([string]$r) }
                }
            }
        }

        foreach ($ref in $refs) {
            if ($ref -eq 'mesh') { continue }

            # Primary resolution: '<ns>/<name>' or '<name>' in the VS namespace.
            $key = if ($ref.Contains('/')) { $ref } else { "$vsNs/$ref" }
            if ($istioKeys.Contains($key)) { continue }

            # Legacy fallback: '<name>.<ns>[.svc.cluster.local]'.
            $legacyKey = $null
            if (-not $ref.Contains('/') -and $ref.Contains('.')) {
                $parts = $ref.Split('.')
                $legacyKey = "$($parts[1])/$($parts[0])"
                if ($istioKeys.Contains($legacyKey)) { continue }
            }

            $hint = 'Either create the Gateway, correct the reference, or remove the stale binding.'
            if ($gwApiKeys.Contains($key) -or ($legacyKey -and $gwApiKeys.Contains($legacyKey))) {
                $hint = "A Gateway API Gateway named '$key' exists, but VirtualServices can only bind to Istio" +
                    ' (networking.istio.io) Gateways. Express this route as an HTTPRoute attached to that' +
                    ' Gateway instead.'
            }

            $g02Message = @(
                "VirtualService '$vsName' in namespace '$vsNs' references gateway '$ref', which resolves to"
                "'$key' but no Istio Gateway with that name exists. Routes bound to that gateway are not"
                "programmed anywhere, so traffic you expect this VirtualService to handle at ingress is not"
                "reaching it today and will not after migration either. $hint"
            ) -join ' '

            Format-Finding `
                -Severity 'Warning' `
                -Category 'Ingress' `
                -CheckId  'G-02' `
                -Resource "VirtualService/$vsName in namespace $vsNs" `
                -Message  $g02Message `
                -DocLink  'https://istio.io/latest/docs/reference/config/networking/virtual-service/#VirtualService'
        }
    }
}
