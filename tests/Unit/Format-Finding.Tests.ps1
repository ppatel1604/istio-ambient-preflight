#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $privateRoot = Resolve-Path "$PSScriptRoot/../../src/IstioAmbientPreflight/Private"
    . (Join-Path $privateRoot 'Format-Finding.ps1')
}

Describe 'Format-Finding' {

    Context 'happy path' {

        It 'returns an object with all six canonical properties populated' {
            $finding = Format-Finding `
                -Severity 'Blocker' `
                -Category 'Network' `
                -CheckId 'C-02' `
                -Resource 'NetworkPolicy/allow-frontend in namespace payments' `
                -Message 'Policy does not allow ztunnel traffic on port 15008.' `
                -DocLink 'https://istio.io/latest/docs/ambient/architecture/traffic-redirection/'

            $finding.Severity | Should -Be 'Blocker'
            $finding.Category | Should -Be 'Network'
            $finding.CheckId  | Should -Be 'C-02'
            $finding.Resource | Should -Be 'NetworkPolicy/allow-frontend in namespace payments'
            $finding.Message  | Should -Be 'Policy does not allow ztunnel traffic on port 15008.'
            $finding.DocLink  | Should -Be 'https://istio.io/latest/docs/ambient/architecture/traffic-redirection/'
        }

        It 'tags the output with the IstioAmbientPreflight.Finding PSTypeName' {
            $finding = Format-Finding `
                -Severity 'Info' `
                -Category 'Labels' `
                -CheckId 'P-01' `
                -Resource 'Pod/demo-app-xyz in namespace demo-app' `
                -Message 'Pod is explicitly opted out via dataplane-mode=none.' `
                -DocLink 'https://istio.io/latest/docs/ambient/usage/add-workloads-to-mesh/'

            $finding.PSObject.TypeNames | Should -Contain 'IstioAmbientPreflight.Finding'
        }

        It 'accepts each of the three valid severity values' {
            foreach ($sev in @('Blocker', 'Warning', 'Info')) {
                $finding = Format-Finding `
                    -Severity $sev `
                    -Category 'Labels' `
                    -CheckId 'N-01' `
                    -Resource 'Namespace/demo-app' `
                    -Message 'Namespace missing istio.io/dataplane-mode=ambient label.' `
                    -DocLink 'https://istio.io/latest/docs/ambient/usage/add-workloads-to-mesh/'
                $finding.Severity | Should -Be $sev
            }
        }
    }

    Context 'validation' {

        It 'rejects a severity outside the allowed set' {
            {
                Format-Finding `
                    -Severity 'Critical' `
                    -Category 'Labels' `
                    -CheckId 'N-01' `
                    -Resource 'Namespace/demo-app' `
                    -Message 'anything' `
                    -DocLink 'https://istio.io/'
            } | Should -Throw
        }

        It 'rejects a CheckId that does not match the stable-id pattern' {
            {
                Format-Finding `
                    -Severity 'Info' `
                    -Category 'Labels' `
                    -CheckId 'nope' `
                    -Resource 'Namespace/demo-app' `
                    -Message 'anything' `
                    -DocLink 'https://istio.io/'
            } | Should -Throw
        }

        It 'rejects a DocLink that is not an http(s) URL' {
            {
                Format-Finding `
                    -Severity 'Info' `
                    -Category 'Labels' `
                    -CheckId 'N-01' `
                    -Resource 'Namespace/demo-app' `
                    -Message 'anything' `
                    -DocLink 'istio.io/docs'
            } | Should -Throw
        }

        It 'rejects an empty Category' {
            {
                Format-Finding `
                    -Severity 'Info' `
                    -Category '' `
                    -CheckId 'N-01' `
                    -Resource 'Namespace/demo-app' `
                    -Message 'anything' `
                    -DocLink 'https://istio.io/'
            } | Should -Throw
        }

        It 'rejects a null Message' {
            {
                Format-Finding `
                    -Severity 'Info' `
                    -Category 'Labels' `
                    -CheckId 'N-01' `
                    -Resource 'Namespace/demo-app' `
                    -Message $null `
                    -DocLink 'https://istio.io/'
            } | Should -Throw
        }
    }
}
