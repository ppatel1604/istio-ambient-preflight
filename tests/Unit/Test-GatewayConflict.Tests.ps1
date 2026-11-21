#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $privateRoot = Resolve-Path "$PSScriptRoot/../../src/IstioAmbientPreflight/Private"
    . (Join-Path $privateRoot 'Format-Finding.ps1')
    . (Join-Path $privateRoot 'Test-GatewayConflict.ps1')

    # Shapes mirror `kubectl get <kind> -o json` items for
    # gateways.networking.istio.io, gateways.gateway.networking.k8s.io and
    # virtualservices.networking.istio.io.
    function New-IstioGateway {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$Namespace,
            [string[]]$Hosts = @()
        )
        [pscustomobject]@{
            metadata = [pscustomobject]@{ name = $Name; namespace = $Namespace }
            spec     = [pscustomobject]@{
                selector = [pscustomobject]@{ istio = 'ingressgateway' }
                servers  = @(
                    [pscustomobject]@{
                        port  = [pscustomobject]@{ number = 80; name = 'http'; protocol = 'HTTP' }
                        hosts = @($Hosts)
                    }
                )
            }
        }
    }

    # Each entry in -Listeners is a hashtable: @{ hostname = '...'; protocol = '...' }.
    # Omitting hostname models a listener that matches every host.
    function New-GwApiGateway {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$Namespace,
            [string]$ClassName = 'istio',
            [hashtable[]]$Listeners = @()
        )
        $listenerObjs = foreach ($l in $Listeners) {
            $obj = [ordered]@{ name = 'l'; port = 80; protocol = 'HTTP' }
            foreach ($k in $l.Keys) { $obj[$k] = $l[$k] }
            [pscustomobject]$obj
        }
        [pscustomobject]@{
            metadata = [pscustomobject]@{ name = $Name; namespace = $Namespace }
            spec     = [pscustomobject]@{
                gatewayClassName = $ClassName
                listeners        = @($listenerObjs)
            }
        }
    }

    function New-VirtualService {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$Namespace,
            [string[]]$Gateways,
            [string[]]$MatchGateways
        )
        $spec = [ordered]@{ hosts = @('demo.example.com') }
        if ($PSBoundParameters.ContainsKey('Gateways')) { $spec.gateways = @($Gateways) }
        $route = [ordered]@{ route = @([pscustomobject]@{ destination = [pscustomobject]@{ host = 'frontend' } }) }
        if ($PSBoundParameters.ContainsKey('MatchGateways')) {
            $route.match = @([pscustomobject]@{ gateways = @($MatchGateways) })
        }
        $spec.http = @([pscustomobject]$route)
        [pscustomobject]@{
            metadata = [pscustomobject]@{ name = $Name; namespace = $Namespace }
            spec     = [pscustomobject]$spec
        }
    }

    function New-Inventory {
        param(
            [object[]]$IstioGateways      = @(),
            [object[]]$GatewayAPIGateways = @(),
            [object[]]$VirtualServices    = @()
        )
        [pscustomobject]@{
            Namespaces            = @()
            Pods                  = @()
            IstioGateways         = @($IstioGateways)
            VirtualServices       = @($VirtualServices)
            DestinationRules      = @()
            CiliumNetworkPolicies = @()
            GatewayAPIGateways    = @($GatewayAPIGateways)
        }
    }
}

Describe 'Test-GatewayConflict (G-01)' {

    It 'emits nothing when the inventory has no gateways or VirtualServices' {
        @(Test-GatewayConflict -Inventory (New-Inventory)).Count | Should -Be 0
    }

    It 'emits nothing when only one API is in use' {
        $inv = New-Inventory -IstioGateways @(New-IstioGateway -Name 'web' -Namespace 'frontend' -Hosts 'shop.example.com')
        @(Test-GatewayConflict -Inventory $inv).Count | Should -Be 0
    }

    It 'emits a Blocker when both APIs claim the same exact host' {
        $inv = New-Inventory `
            -IstioGateways @(New-IstioGateway -Name 'web' -Namespace 'frontend' -Hosts 'shop.example.com') `
            -GatewayAPIGateways @(New-GwApiGateway -Name 'web-gw' -Namespace 'frontend' -Listeners @{ hostname = 'shop.example.com' })

        $findings = @(Test-GatewayConflict -Inventory $inv)

        $findings.Count       | Should -Be 1
        $findings[0].CheckId  | Should -Be 'G-01'
        $findings[0].Severity | Should -Be 'Blocker'
        $findings[0].Category | Should -Be 'Ingress'
        $findings[0].Resource | Should -Be 'Gateway/web in namespace frontend (Istio) + Gateway/web-gw in namespace frontend (Gateway API)'
        $findings[0].Message  | Should -Match "'shop\.example\.com'"
        $findings[0].DocLink  | Should -Match '^https://istio\.io/'
    }

    It 'compares hosts case-insensitively and strips the Istio namespace/ prefix' {
        $inv = New-Inventory `
            -IstioGateways @(New-IstioGateway -Name 'web' -Namespace 'frontend' -Hosts 'payments-ns/Shop.Example.com') `
            -GatewayAPIGateways @(New-GwApiGateway -Name 'web-gw' -Namespace 'frontend' -Listeners @{ hostname = 'shop.example.com' })

        @(Test-GatewayConflict -Inventory $inv).Count | Should -Be 1
    }

    It 'emits nothing when hostnames are disjoint' {
        $inv = New-Inventory `
            -IstioGateways @(New-IstioGateway -Name 'web' -Namespace 'frontend' -Hosts 'shop.example.com') `
            -GatewayAPIGateways @(New-GwApiGateway -Name 'api-gw' -Namespace 'frontend' -Listeners @{ hostname = 'api.example.com' })

        @(Test-GatewayConflict -Inventory $inv).Count | Should -Be 0
    }

    It 'treats a wildcard as overlapping a host under that domain' {
        $inv = New-Inventory `
            -IstioGateways @(New-IstioGateway -Name 'web' -Namespace 'frontend' -Hosts '*.example.com') `
            -GatewayAPIGateways @(New-GwApiGateway -Name 'api-gw' -Namespace 'frontend' -Listeners @{ hostname = 'api.example.com' })

        $findings = @(Test-GatewayConflict -Inventory $inv)
        $findings.Count      | Should -Be 1
        $findings[0].Message | Should -Match "'\*\.example\.com' \(Istio\) vs 'api\.example\.com' \(Gateway API\)"
    }

    It 'does not treat a wildcard as matching the bare parent domain' {
        $inv = New-Inventory `
            -IstioGateways @(New-IstioGateway -Name 'web' -Namespace 'frontend' -Hosts '*.example.com') `
            -GatewayAPIGateways @(New-GwApiGateway -Name 'apex-gw' -Namespace 'frontend' -Listeners @{ hostname = 'example.com' })

        @(Test-GatewayConflict -Inventory $inv).Count | Should -Be 0
    }

    It 'treats nested wildcards as overlapping' {
        $inv = New-Inventory `
            -IstioGateways @(New-IstioGateway -Name 'web' -Namespace 'frontend' -Hosts '*.example.com') `
            -GatewayAPIGateways @(New-GwApiGateway -Name 'eu-gw' -Namespace 'frontend' -Listeners @{ hostname = '*.eu.example.com' })

        @(Test-GatewayConflict -Inventory $inv).Count | Should -Be 1
    }

    It 'treats a Gateway API listener with no hostname as matching every host' {
        $inv = New-Inventory `
            -IstioGateways @(New-IstioGateway -Name 'web' -Namespace 'frontend' -Hosts 'shop.example.com') `
            -GatewayAPIGateways @(New-GwApiGateway -Name 'catch-all' -Namespace 'frontend' -Listeners @{ protocol = 'HTTP' })

        @(Test-GatewayConflict -Inventory $inv).Count | Should -Be 1
    }

    It 'treats an Istio "*" host as matching every host' {
        $inv = New-Inventory `
            -IstioGateways @(New-IstioGateway -Name 'web' -Namespace 'frontend' -Hosts '*') `
            -GatewayAPIGateways @(New-GwApiGateway -Name 'api-gw' -Namespace 'frontend' -Listeners @{ hostname = 'api.example.com' })

        @(Test-GatewayConflict -Inventory $inv).Count | Should -Be 1
    }

    It 'ignores waypoint and east-west Gateway API Gateways (mesh infrastructure, not ingress)' {
        $inv = New-Inventory `
            -IstioGateways @(New-IstioGateway -Name 'web' -Namespace 'frontend' -Hosts '*') `
            -GatewayAPIGateways @(
                New-GwApiGateway -Name 'waypoint' -Namespace 'payments-ns' -ClassName 'istio-waypoint' -Listeners @{ protocol = 'HBONE'; port = 15008 }
                New-GwApiGateway -Name 'eastwest' -Namespace 'istio-system' -ClassName 'istio-east-west' -Listeners @{ protocol = 'TLS'; port = 15008 }
                New-GwApiGateway -Name 'hbone-only' -Namespace 'demo-app' -Listeners @{ protocol = 'HBONE'; port = 15008 }
            )

        @(Test-GatewayConflict -Inventory $inv).Count | Should -Be 0
    }

    It 'emits one finding per overlapping gateway pair and lists every overlapping host' {
        $inv = New-Inventory `
            -IstioGateways @(
                New-IstioGateway -Name 'web' -Namespace 'frontend' -Hosts 'shop.example.com', 'api.example.com'
                New-IstioGateway -Name 'admin' -Namespace 'frontend' -Hosts 'admin.example.com'
            ) `
            -GatewayAPIGateways @(New-GwApiGateway -Name 'web-gw' -Namespace 'frontend' -Listeners @(
                    @{ hostname = 'shop.example.com' }
                    @{ hostname = 'api.example.com' }
                ))

        $findings = @(Test-GatewayConflict -Inventory $inv)
        $findings.Count      | Should -Be 1
        $findings[0].Message | Should -Match 'shop\.example\.com'
        $findings[0].Message | Should -Match 'api\.example\.com'
    }

    It 'with -Namespace, reports a pair only when either gateway is in that namespace' {
        $inv = New-Inventory `
            -IstioGateways @(New-IstioGateway -Name 'web' -Namespace 'istio-ingress' -Hosts 'shop.example.com') `
            -GatewayAPIGateways @(New-GwApiGateway -Name 'web-gw' -Namespace 'frontend' -Listeners @{ hostname = 'shop.example.com' })

        @(Test-GatewayConflict -Inventory $inv -Namespace 'frontend').Count      | Should -Be 1
        @(Test-GatewayConflict -Inventory $inv -Namespace 'istio-ingress').Count | Should -Be 1
        @(Test-GatewayConflict -Inventory $inv -Namespace 'payments-ns').Count   | Should -Be 0
    }
}

Describe 'Test-GatewayConflict (G-02)' {

    It 'emits nothing when an unqualified reference resolves in the VirtualService namespace' {
        $inv = New-Inventory `
            -IstioGateways @(New-IstioGateway -Name 'web' -Namespace 'frontend' -Hosts 'shop.example.com') `
            -VirtualServices @(New-VirtualService -Name 'shop' -Namespace 'frontend' -Gateways 'web')

        @(Test-GatewayConflict -Inventory $inv).Count | Should -Be 0
    }

    It 'emits nothing when a namespace-qualified reference resolves' {
        $inv = New-Inventory `
            -IstioGateways @(New-IstioGateway -Name 'web' -Namespace 'istio-ingress' -Hosts 'shop.example.com') `
            -VirtualServices @(New-VirtualService -Name 'shop' -Namespace 'frontend' -Gateways 'istio-ingress/web')

        @(Test-GatewayConflict -Inventory $inv).Count | Should -Be 0
    }

    It 'resolves the legacy <name>.<namespace>.svc.cluster.local form' {
        $inv = New-Inventory `
            -IstioGateways @(New-IstioGateway -Name 'web' -Namespace 'istio-ingress' -Hosts 'shop.example.com') `
            -VirtualServices @(New-VirtualService -Name 'shop' -Namespace 'frontend' -Gateways 'web.istio-ingress.svc.cluster.local')

        @(Test-GatewayConflict -Inventory $inv).Count | Should -Be 0
    }

    It 'ignores the reserved "mesh" gateway' {
        $inv = New-Inventory -VirtualServices @(New-VirtualService -Name 'internal' -Namespace 'payments-ns' -Gateways 'mesh')

        @(Test-GatewayConflict -Inventory $inv).Count | Should -Be 0
    }

    It 'emits nothing for a VirtualService with no gateways field' {
        $inv = New-Inventory -VirtualServices @(New-VirtualService -Name 'internal' -Namespace 'payments-ns')

        @(Test-GatewayConflict -Inventory $inv).Count | Should -Be 0
    }

    It 'emits a Warning when an unqualified reference does not resolve (wrong namespace)' {
        # 'web' exists, but in istio-ingress; an unqualified ref from
        # 'frontend' resolves to frontend/web, which does not exist.
        $inv = New-Inventory `
            -IstioGateways @(New-IstioGateway -Name 'web' -Namespace 'istio-ingress' -Hosts 'shop.example.com') `
            -VirtualServices @(New-VirtualService -Name 'shop' -Namespace 'frontend' -Gateways 'web')

        $findings = @(Test-GatewayConflict -Inventory $inv)

        $findings.Count       | Should -Be 1
        $findings[0].CheckId  | Should -Be 'G-02'
        $findings[0].Severity | Should -Be 'Warning'
        $findings[0].Category | Should -Be 'Ingress'
        $findings[0].Resource | Should -Be 'VirtualService/shop in namespace frontend'
        $findings[0].Message  | Should -Match "'frontend/web'"
        $findings[0].DocLink  | Should -Match '^https://istio\.io/'
    }

    It 'checks gateways referenced from http[].match[].gateways' {
        $inv = New-Inventory `
            -IstioGateways @(New-IstioGateway -Name 'web' -Namespace 'frontend' -Hosts 'shop.example.com') `
            -VirtualServices @(New-VirtualService -Name 'shop' -Namespace 'frontend' -Gateways 'web' -MatchGateways 'frontend/old-web')

        $findings = @(Test-GatewayConflict -Inventory $inv)
        $findings.Count      | Should -Be 1
        $findings[0].Message | Should -Match "'frontend/old-web'"
    }

    It 'reports each distinct dangling reference once' {
        $inv = New-Inventory -VirtualServices @(
            New-VirtualService -Name 'shop' -Namespace 'frontend' -Gateways 'gone-a', 'gone-b' -MatchGateways 'gone-a'
        )

        @(Test-GatewayConflict -Inventory $inv).Count | Should -Be 2
    }

    It 'explains when the reference names a Gateway API Gateway instead of an Istio Gateway' {
        $inv = New-Inventory `
            -GatewayAPIGateways @(New-GwApiGateway -Name 'web-gw' -Namespace 'frontend' -Listeners @{ hostname = 'shop.example.com' }) `
            -VirtualServices @(New-VirtualService -Name 'shop' -Namespace 'frontend' -Gateways 'web-gw')

        $findings = @(Test-GatewayConflict -Inventory $inv)
        $findings.Count      | Should -Be 1
        $findings[0].Message | Should -Match 'HTTPRoute'
    }

    It 'with -Namespace, considers only VirtualServices in that namespace' {
        $inv = New-Inventory -VirtualServices @(
            New-VirtualService -Name 'shop' -Namespace 'frontend' -Gateways 'gone'
            New-VirtualService -Name 'pay' -Namespace 'payments-ns' -Gateways 'gone'
        )

        $findings = @(Test-GatewayConflict -Inventory $inv -Namespace 'payments-ns')
        $findings.Count       | Should -Be 1
        $findings[0].Resource | Should -Be 'VirtualService/pay in namespace payments-ns'
    }

    It 'tolerates an inventory missing the gateway and VirtualService properties' {
        $inv = [pscustomobject]@{ Namespaces = @() }
        { Test-GatewayConflict -Inventory $inv } | Should -Not -Throw
    }
}
