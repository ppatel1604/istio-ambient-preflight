#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $privateRoot = Resolve-Path "$PSScriptRoot/../../src/IstioAmbientPreflight/Private"
    . (Join-Path $privateRoot 'Invoke-Kubectl.ps1')
    . (Join-Path $privateRoot 'Get-ClusterInventory.ps1')

    function New-KubeList {
        param([string]$Kind, [object[]]$Items = @())
        [pscustomobject]@{
            apiVersion = 'v1'
            kind       = "${Kind}List"
            items      = @($Items)
        }
    }

    function New-NamespaceItem {
        param([string]$Name, [hashtable]$Labels = @{})
        [pscustomobject]@{
            metadata = [pscustomobject]@{
                name   = $Name
                labels = [pscustomobject]$Labels
            }
        }
    }
}

Describe 'Get-ClusterInventory' {

    Context 'all CRDs installed' {

        It 'returns a typed list for each resource kind' {
            Mock Invoke-Kubectl -ParameterFilter { $Arguments -contains 'namespaces' } -MockWith {
                New-KubeList -Kind 'Namespace' -Items @(New-NamespaceItem -Name 'demo-app')
            }
            Mock Invoke-Kubectl -ParameterFilter { $Arguments -contains 'pods' } -MockWith {
                New-KubeList -Kind 'Pod' -Items @([pscustomobject]@{ metadata = [pscustomobject]@{ name = 'p1'; namespace = 'demo-app' } })
            }
            Mock Invoke-Kubectl -ParameterFilter { $Arguments -contains 'gateways.networking.istio.io' } -MockWith {
                New-KubeList -Kind 'Gateway' -Items @([pscustomobject]@{ metadata = [pscustomobject]@{ name = 'istio-gw'; namespace = 'istio-system' } })
            }
            Mock Invoke-Kubectl -ParameterFilter { $Arguments -contains 'virtualservices.networking.istio.io' } -MockWith {
                New-KubeList -Kind 'VirtualService'
            }
            Mock Invoke-Kubectl -ParameterFilter { $Arguments -contains 'destinationrules.networking.istio.io' } -MockWith {
                New-KubeList -Kind 'DestinationRule'
            }
            Mock Invoke-Kubectl -ParameterFilter { $Arguments -contains 'ciliumnetworkpolicies.cilium.io' } -MockWith {
                New-KubeList -Kind 'CiliumNetworkPolicy' -Items @([pscustomobject]@{ metadata = [pscustomobject]@{ name = 'cnp-1'; namespace = 'demo-app' } })
            }
            Mock Invoke-Kubectl -ParameterFilter { $Arguments -contains 'gateways.gateway.networking.k8s.io' } -MockWith {
                New-KubeList -Kind 'Gateway'
            }

            $inv = Get-ClusterInventory

            $inv.Namespaces.Count            | Should -Be 1
            $inv.Pods.Count                  | Should -Be 1
            $inv.IstioGateways.Count         | Should -Be 1
            $inv.VirtualServices.Count       | Should -Be 0
            $inv.DestinationRules.Count      | Should -Be 0
            $inv.CiliumNetworkPolicies.Count | Should -Be 1
            $inv.GatewayAPIGateways.Count    | Should -Be 0
        }

        It 'passes --context when -Context is supplied' {
            Mock Invoke-Kubectl -MockWith { New-KubeList -Kind 'Namespace' }

            Get-ClusterInventory -Context 'my-cluster' | Out-Null

            Should -Invoke Invoke-Kubectl -Times 7 -ParameterFilter { $Context -eq 'my-cluster' }
        }

        It 'omits --all-namespaces for cluster-scoped namespaces but includes it for namespaced kinds' {
            Mock Invoke-Kubectl -MockWith { New-KubeList -Kind 'Namespace' }

            Get-ClusterInventory | Out-Null

            Should -Invoke Invoke-Kubectl -ParameterFilter {
                ($Arguments -contains 'namespaces') -and -not ($Arguments -contains '--all-namespaces')
            }
            Should -Invoke Invoke-Kubectl -ParameterFilter {
                ($Arguments -contains 'pods') -and ($Arguments -contains '--all-namespaces')
            }
        }
    }

    Context 'CRD not installed' {

        It 'returns an empty array for the Cilium resource when the CRD is missing' {
            Mock Invoke-Kubectl -MockWith { New-KubeList -Kind 'Namespace' }
            Mock Invoke-Kubectl -ParameterFilter { $Arguments -contains 'ciliumnetworkpolicies.cilium.io' } -MockWith {
                throw "kubectl exited with code 1. Command: kubectl get ciliumnetworkpolicies.cilium.io -o json`nStderr: error: the server doesn't have a resource type `"ciliumnetworkpolicies`""
            }

            $inv = Get-ClusterInventory

            ($inv.CiliumNetworkPolicies -is [array]) | Should -BeTrue
            $inv.CiliumNetworkPolicies.Count | Should -Be 0
            $inv.Namespaces.Count | Should -Be 0  # empty List still returns
        }

        It 'matches the alternative "server could not find the requested resource" phrasing' {
            Mock Invoke-Kubectl -MockWith { New-KubeList -Kind 'Namespace' }
            Mock Invoke-Kubectl -ParameterFilter { $Arguments -contains 'gateways.gateway.networking.k8s.io' } -MockWith {
                throw 'kubectl exited with code 1. Command: kubectl get gateways.gateway.networking.k8s.io -o json\nStderr: error: the server could not find the requested resource'
            }

            $inv = Get-ClusterInventory

            $inv.GatewayAPIGateways.Count | Should -Be 0
        }

        It 'rethrows kubectl errors that are not CRD-missing errors' {
            Mock Invoke-Kubectl -MockWith { New-KubeList -Kind 'Namespace' }
            Mock Invoke-Kubectl -ParameterFilter { $Arguments -contains 'pods' } -MockWith {
                throw 'kubectl exited with code 1. Command: kubectl get pods --all-namespaces -o json`nStderr: Error from server (Forbidden): pods is forbidden'
            }

            { Get-ClusterInventory } | Should -Throw -ExpectedMessage '*Forbidden*'
        }
    }
}
