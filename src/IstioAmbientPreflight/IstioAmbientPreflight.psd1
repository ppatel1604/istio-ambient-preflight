@{
    RootModule           = 'IstioAmbientPreflight.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'b2d3c8a4-4f6b-4a2e-9c1f-6f3a8e5b21ad'
    Author               = 'Parth Patel'
    CompanyName          = 'Parth Patel'
    Copyright            = '(c) 2026 Parth Patel. Released under the MIT License.'
    Description          = 'Read-only preflight checks for migrating a Kubernetes cluster to Istio Ambient Mode. Flags silent compatibility problems in namespace labels, Cilium NetworkPolicies, and Gateway configurations before you flip the switch.'
    PowerShellVersion    = '7.0'
    CompatiblePSEditions = @('Core')

    FunctionsToExport    = @(
        'Invoke-AmbientPreflight'
        'New-AmbientMigrationReport'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @('Istio', 'Ambient', 'Kubernetes', 'ServiceMesh', 'Cilium', 'GatewayAPI', 'Preflight', 'Migration', 'Linux', 'MacOS', 'Windows')
            LicenseUri   = 'https://github.com/ppatel1604/istio-ambient-preflight/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/ppatel1604/istio-ambient-preflight'
            ReleaseNotes = 'See CHANGELOG.md at https://github.com/ppatel1604/istio-ambient-preflight/blob/main/CHANGELOG.md'
        }
    }
}
