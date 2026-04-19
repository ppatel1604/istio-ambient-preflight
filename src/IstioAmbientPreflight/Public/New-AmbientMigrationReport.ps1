function New-AmbientMigrationReport {
    <#
    .SYNOPSIS
        Writes a markdown readiness report from a set of findings.

    .DESCRIPTION
        Renders findings produced by the ambient-compatibility checks into a
        markdown document with:

          - A header containing cluster context and generation timestamp.
          - A readiness verdict derived from the highest severity present:
              Blocker  -> "Blocked"
              Warning  -> "Ready with Warnings"
              (none / Info only) -> "Ready"
          - A summary table of counts by severity.
          - Three sections (Blockers, Warnings, Info) with one subsection per
            finding. Sections are always emitted, with an explicit "(none)"
            when empty, so downstream tooling can rely on the structure.

        The report is written to OutputPath (parent directory created if
        needed) and the resolved absolute path is returned.

    .PARAMETER Findings
        Array of finding objects produced by Format-Finding. May be empty.

    .PARAMETER OutputPath
        Path of the markdown file to write. Parent directories will be created
        if they do not already exist.

    .PARAMETER Context
        Kubectl context name to record in the report header. Optional.

    .PARAMETER GeneratedAt
        Timestamp to record in the report header. Defaults to the current time;
        overridable to make tests deterministic.

    .EXAMPLE
        PS> New-AmbientMigrationReport -Findings $findings -OutputPath ./report.md -Context my-cluster

    .OUTPUTS
        System.String - the absolute path of the written report.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath,

        [Parameter()]
        [string]$Context,

        [Parameter()]
        [datetime]$GeneratedAt = (Get-Date)
    )

    $byCategory = @{
        Blocker = @($Findings | Where-Object { $_.Severity -eq 'Blocker' })
        Warning = @($Findings | Where-Object { $_.Severity -eq 'Warning' })
        Info    = @($Findings | Where-Object { $_.Severity -eq 'Info'    })
    }

    $verdict = if ($byCategory.Blocker.Count -gt 0) {
        'Blocked'
    } elseif ($byCategory.Warning.Count -gt 0) {
        'Ready with Warnings'
    } else {
        'Ready'
    }

    $contextLabel = if ([string]::IsNullOrWhiteSpace($Context)) { '(current kubeconfig context)' } else { $Context }

    # Emoji are expressed via `u{xxxx} escapes so the source file stays ASCII
    # (per CLAUDE.md: UTF-8 without BOM). The rendered markdown still contains
    # the real code points.
    $iconBlocker = "`u{1F534}"  # Red circle
    $iconWarning = "`u{1F7E1}"  # Yellow circle
    $iconInfo    = "`u{1F535}"  # Blue circle

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Istio Ambient Preflight Report')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("**Generated:** $($GeneratedAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))  ")
    [void]$sb.AppendLine("**Context:** $contextLabel  ")
    [void]$sb.AppendLine("**Verdict:** $verdict")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## Summary')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Severity | Count |')
    [void]$sb.AppendLine('|---|---|')
    [void]$sb.AppendLine("| $iconBlocker Blocker | $($byCategory.Blocker.Count) |")
    [void]$sb.AppendLine("| $iconWarning Warning | $($byCategory.Warning.Count) |")
    [void]$sb.AppendLine("| $iconInfo Info | $($byCategory.Info.Count) |")
    [void]$sb.AppendLine()

    $sections = @(
        @{ Title = 'Blockers'; Icon = $iconBlocker; Key = 'Blocker' }
        @{ Title = 'Warnings'; Icon = $iconWarning; Key = 'Warning' }
        @{ Title = 'Info';     Icon = $iconInfo;    Key = 'Info'    }
    )

    foreach ($section in $sections) {
        [void]$sb.AppendLine("## $($section.Icon) $($section.Title)")
        [void]$sb.AppendLine()
        $items = $byCategory[$section.Key]
        if ($items.Count -eq 0) {
            [void]$sb.AppendLine('_(none)_')
            [void]$sb.AppendLine()
            continue
        }
        foreach ($f in $items) {
            [void]$sb.AppendLine("### $($f.CheckId) `u{00B7} $($f.Category) `u{00B7} $($f.Resource)")
            [void]$sb.AppendLine()
            [void]$sb.AppendLine($f.Message)
            [void]$sb.AppendLine()
            [void]$sb.AppendLine("**Reference:** $($f.DocLink)")
            [void]$sb.AppendLine()
        }
    }

    $parent = Split-Path -Parent -Path $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        if ($PSCmdlet.ShouldProcess($parent, 'Create report output directory')) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
    }

    if (-not $PSCmdlet.ShouldProcess($OutputPath, 'Write ambient preflight markdown report')) {
        return $OutputPath
    }

    [System.IO.File]::WriteAllText($OutputPath, $sb.ToString())

    return (Resolve-Path -LiteralPath $OutputPath).Path
}
