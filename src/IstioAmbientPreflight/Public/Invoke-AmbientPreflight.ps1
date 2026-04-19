function Invoke-AmbientPreflight {
    <#
    .SYNOPSIS
        Scans a Kubernetes cluster and writes an Istio Ambient readiness report.

    .DESCRIPTION
        Top-level entry point for the IstioAmbientPreflight module. Runs in three
        phases:

          1. Collect a single-pass cluster inventory via Get-ClusterInventory.
          2. Run every compatibility check against that cached inventory.
          3. Render the findings to a markdown report via New-AmbientMigrationReport.

        The tool is strictly read-only. It never mutates cluster state.

    .PARAMETER Context
        Name of the kubectl context to target. When omitted, the current
        kubeconfig context is used.

    .PARAMETER OutputPath
        Path of the markdown report. Defaults to
        './ambient-preflight-report.md' in the current working directory.

    .PARAMETER Namespace
        Optional filter. When supplied, checks consider only this namespace.
        Useful for scoped reviews of a single team or application.

    .EXAMPLE
        PS> Invoke-AmbientPreflight
        Runs against the current kubectl context, writes
        ./ambient-preflight-report.md, and returns a result object.

    .EXAMPLE
        PS> Invoke-AmbientPreflight -Context prod-us-east -OutputPath ./reports/prod.md

    .EXAMPLE
        PS> Invoke-AmbientPreflight -Namespace payments

    .OUTPUTS
        PSCustomObject with fields:
            ReportPath   - absolute path of the written report
            FindingCount - total findings across all severities
            BlockerCount - count of Blocker findings
            WarningCount - count of Warning findings
            InfoCount    - count of Info findings
            Findings     - the raw finding objects
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Write-Host is intentional for user-facing progress output per the project conventions in CLAUDE.md; findings and the result object are emitted via Write-Output.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$Context,

        [Parameter()]
        [string]$OutputPath = (Join-Path -Path (Get-Location).Path -ChildPath 'ambient-preflight-report.md'),

        [Parameter()]
        [string]$Namespace
    )

    Write-Host 'istio-ambient-preflight' -ForegroundColor Cyan
    Write-Host '-----------------------'

    $inventoryParams = @{}
    if ($PSBoundParameters.ContainsKey('Context') -and -not [string]::IsNullOrWhiteSpace($Context)) {
        $inventoryParams.Context = $Context
    }

    Write-Host 'Collecting cluster inventory...'
    $inventory = Get-ClusterInventory @inventoryParams

    Write-Host ('  namespaces={0} pods={1} istio-gateways={2} virtualservices={3} destinationrules={4} cilium-nps={5} gwapi-gateways={6}' -f `
            $inventory.Namespaces.Count,
        $inventory.Pods.Count,
        $inventory.IstioGateways.Count,
        $inventory.VirtualServices.Count,
        $inventory.DestinationRules.Count,
        $inventory.CiliumNetworkPolicies.Count,
        $inventory.GatewayAPIGateways.Count)

    Write-Host 'Running compatibility checks...'

    $checkParams = @{ Inventory = $inventory }
    if ($PSBoundParameters.ContainsKey('Namespace') -and -not [string]::IsNullOrWhiteSpace($Namespace)) {
        $checkParams.Namespace = $Namespace
    }

    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($finding in @(Test-NamespaceLabels @checkParams)) {
        $findings.Add($finding)
    }
    # Future checks plug in here.

    Write-Host ('  findings={0}' -f $findings.Count)
    Write-Host 'Writing report...'

    $reportParams = @{
        Findings   = $findings.ToArray()
        OutputPath = $OutputPath
    }
    if ($PSBoundParameters.ContainsKey('Context') -and -not [string]::IsNullOrWhiteSpace($Context)) {
        $reportParams.Context = $Context
    }
    $path = New-AmbientMigrationReport @reportParams

    $blockerCount = @($findings | Where-Object { $_.Severity -eq 'Blocker' }).Count
    $warningCount = @($findings | Where-Object { $_.Severity -eq 'Warning' }).Count
    $infoCount    = @($findings | Where-Object { $_.Severity -eq 'Info' }).Count

    Write-Host ("Report written: $path") -ForegroundColor Green

    [pscustomobject]@{
        ReportPath   = $path
        FindingCount = $findings.Count
        BlockerCount = $blockerCount
        WarningCount = $warningCount
        InfoCount    = $infoCount
        Findings     = $findings.ToArray()
    }
}
