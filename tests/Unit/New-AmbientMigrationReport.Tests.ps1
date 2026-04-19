#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot    = Resolve-Path "$PSScriptRoot/../.."
    $privateRoot = Join-Path $repoRoot 'src/IstioAmbientPreflight/Private'
    $publicRoot  = Join-Path $repoRoot 'src/IstioAmbientPreflight/Public'

    . (Join-Path $privateRoot 'Format-Finding.ps1')
    . (Join-Path $publicRoot  'New-AmbientMigrationReport.ps1')

    function New-TestFinding {
        param(
            [Parameter(Mandatory)][string]$Severity,
            [string]$CheckId  = 'N-01',
            [string]$Category = 'Labels',
            [string]$Resource = 'Namespace/demo-app',
            [string]$Message  = 'Example message.',
            [string]$DocLink  = 'https://istio.io/latest/docs/ambient/usage/add-workloads/'
        )
        Format-Finding -Severity $Severity -Category $Category -CheckId $CheckId `
            -Resource $Resource -Message $Message -DocLink $DocLink
    }
}

Describe 'New-AmbientMigrationReport' {

    BeforeEach {
        $script:tmpReport = Join-Path ([System.IO.Path]::GetTempPath()) ("iap-report-" + [guid]::NewGuid() + '.md')
    }

    AfterEach {
        if (Test-Path $script:tmpReport) { Remove-Item $script:tmpReport -Force -ErrorAction SilentlyContinue }
    }

    It 'writes Verdict "Ready" when there are no findings' {
        New-AmbientMigrationReport -Findings @() -OutputPath $script:tmpReport | Out-Null
        $content = Get-Content -LiteralPath $script:tmpReport -Raw
        $content | Should -Match '\*\*Verdict:\*\* Ready\s'
    }

    It 'writes Verdict "Ready" when only Info findings are present' {
        $findings = @(New-TestFinding -Severity 'Info' -CheckId 'P-01')
        New-AmbientMigrationReport -Findings $findings -OutputPath $script:tmpReport | Out-Null
        $content = Get-Content -LiteralPath $script:tmpReport -Raw
        $content | Should -Match '\*\*Verdict:\*\* Ready\s'
    }

    It 'writes Verdict "Ready with Warnings" when there is a Warning but no Blocker' {
        $findings = @(New-TestFinding -Severity 'Warning')
        New-AmbientMigrationReport -Findings $findings -OutputPath $script:tmpReport | Out-Null
        $content = Get-Content -LiteralPath $script:tmpReport -Raw
        $content | Should -Match '\*\*Verdict:\*\* Ready with Warnings'
    }

    It 'writes Verdict "Blocked" when any Blocker is present' {
        $findings = @(
            New-TestFinding -Severity 'Warning'
            New-TestFinding -Severity 'Blocker' -CheckId 'C-02' -Category 'Network'
            New-TestFinding -Severity 'Info'    -CheckId 'P-01'
        )
        New-AmbientMigrationReport -Findings $findings -OutputPath $script:tmpReport | Out-Null
        $content = Get-Content -LiteralPath $script:tmpReport -Raw
        $content | Should -Match '\*\*Verdict:\*\* Blocked'
    }

    It 'emits all three severity sections regardless of whether they contain findings' {
        New-AmbientMigrationReport -Findings @() -OutputPath $script:tmpReport | Out-Null
        $content = Get-Content -LiteralPath $script:tmpReport -Raw
        $content | Should -Match '## 🔴 Blockers'
        $content | Should -Match '## 🟡 Warnings'
        $content | Should -Match '## 🔵 Info'
        # Empty sections are marked with _(none)_
        ([regex]::Matches($content, '_\(none\)_')).Count | Should -Be 3
    }

    It 'renders CheckId, Resource, Message, and DocLink for each finding' {
        $findings = @(
            New-TestFinding -Severity 'Blocker' -CheckId 'C-02' -Category 'Network' `
                -Resource 'NetworkPolicy/allow-frontend in namespace payments' `
                -Message  'Policy does not allow ztunnel traffic on port 15008.' `
                -DocLink  'https://istio.io/latest/docs/ambient/architecture/traffic-redirection/'
        )
        New-AmbientMigrationReport -Findings $findings -OutputPath $script:tmpReport | Out-Null
        $content = Get-Content -LiteralPath $script:tmpReport -Raw
        $content | Should -Match 'C-02'
        $content | Should -Match 'NetworkPolicy/allow-frontend in namespace payments'
        $content | Should -Match 'port 15008'
        $content | Should -Match 'https://istio.io/latest/docs/ambient/architecture/traffic-redirection/'
    }

    It 'records the Context value in the header when supplied' {
        New-AmbientMigrationReport -Findings @() -OutputPath $script:tmpReport -Context 'prod-us-east' | Out-Null
        $content = Get-Content -LiteralPath $script:tmpReport -Raw
        $content | Should -Match '\*\*Context:\*\* prod-us-east'
    }

    It 'records a placeholder context label when none is supplied' {
        New-AmbientMigrationReport -Findings @() -OutputPath $script:tmpReport | Out-Null
        $content = Get-Content -LiteralPath $script:tmpReport -Raw
        $content | Should -Match '\*\*Context:\*\* \(current kubeconfig context\)'
    }

    It 'renders counts in the summary table' {
        $findings = @(
            New-TestFinding -Severity 'Blocker' -CheckId 'C-02' -Category 'Network'
            New-TestFinding -Severity 'Warning' -CheckId 'N-01'
            New-TestFinding -Severity 'Warning' -CheckId 'N-01'
            New-TestFinding -Severity 'Info'    -CheckId 'P-01'
        )
        New-AmbientMigrationReport -Findings $findings -OutputPath $script:tmpReport | Out-Null
        $content = Get-Content -LiteralPath $script:tmpReport -Raw
        $content | Should -Match '\| 🔴 Blocker \| 1 \|'
        $content | Should -Match '\| 🟡 Warning \| 2 \|'
        $content | Should -Match '\| 🔵 Info \| 1 \|'
    }

    It 'returns the absolute path of the written report' {
        $result = New-AmbientMigrationReport -Findings @() -OutputPath $script:tmpReport
        $result | Should -Be (Resolve-Path -LiteralPath $script:tmpReport).Path
        Test-Path -LiteralPath $result | Should -BeTrue
    }

    It 'creates the parent directory when OutputPath points into a missing folder' {
        $nestedDir  = Join-Path ([System.IO.Path]::GetTempPath()) ("iap-nested-" + [guid]::NewGuid())
        $nestedPath = Join-Path $nestedDir 'report.md'
        try {
            New-AmbientMigrationReport -Findings @() -OutputPath $nestedPath | Out-Null
            Test-Path -LiteralPath $nestedPath | Should -BeTrue
        } finally {
            if (Test-Path $nestedDir) { Remove-Item $nestedDir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
