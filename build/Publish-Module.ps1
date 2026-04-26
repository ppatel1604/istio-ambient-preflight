#Requires -Version 7.0
<#
.SYNOPSIS
    Pre-publish dry run for IstioAmbientPreflight.

.DESCRIPTION
    Validates the module manifest, runs PSScriptAnalyzer, runs the Pester
    unit suite, and stages a publish-ready copy of the module under
    .stage/IstioAmbientPreflight. Does NOT actually upload anything to
    PowerShell Gallery -- that step is intentionally manual and
    documented in RELEASING.md.

    Invariants this enforces before a release can go out:
      * Manifest parses with Test-ModuleManifest (catches malformed
        psd1, missing files, exported-function typos).
      * PSScriptAnalyzer is clean against ./src.
      * All unit tests pass.

    On success the script prints the exact Publish-Module command the
    maintainer needs to run to actually publish.

.PARAMETER RepoRoot
    Repository root. Defaults to the parent of this script's directory.

.PARAMETER StagePath
    Where to write the staged module. Defaults to <repo>/.stage.

.EXAMPLE
    PS> ./build/Publish-Module.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$StagePath
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
}
if (-not $StagePath) {
    $StagePath = Join-Path $RepoRoot '.stage'
}

$srcRoot    = Join-Path $RepoRoot 'src'
$modulePath = Join-Path $srcRoot 'IstioAmbientPreflight'
$manifest   = Join-Path $modulePath 'IstioAmbientPreflight.psd1'

function Write-Step([string]$msg) {
    Write-Host ''
    Write-Host "==> $msg" -ForegroundColor Cyan
}

# ---- 1. Manifest ---------------------------------------------------------
Write-Step 'Validating module manifest'
$info = Test-ModuleManifest -Path $manifest
'    Name:    {0}' -f $info.Name        | Write-Host
'    Version: {0}' -f $info.Version     | Write-Host
'    Author:  {0}' -f $info.Author      | Write-Host
'    Exports: {0}' -f (($info.ExportedFunctions.Keys | Sort-Object) -join ', ') | Write-Host

# ---- 2. PSScriptAnalyzer -------------------------------------------------
Write-Step 'Running PSScriptAnalyzer against ./src'
if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
    throw 'PSScriptAnalyzer is not installed. Install-Module PSScriptAnalyzer -Scope CurrentUser'
}
Import-Module PSScriptAnalyzer -ErrorAction Stop
$analyzerResults = Invoke-ScriptAnalyzer -Path $srcRoot -Recurse -Severity @('Error', 'Warning')
if ($analyzerResults) {
    $analyzerResults | Format-Table -AutoSize | Out-String | Write-Host
    throw "PSScriptAnalyzer reported $($analyzerResults.Count) issue(s). Fix them before publishing."
}
'    clean.' | Write-Host

# ---- 3. Pester -----------------------------------------------------------
Write-Step 'Running Pester unit suite'
if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.0.0' })) {
    throw 'Pester 5.x is not installed. Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser'
}
Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
$cfg = New-PesterConfiguration
$cfg.Run.Path     = Join-Path $RepoRoot 'tests/Unit'
$cfg.Run.PassThru = $true
$cfg.Output.Verbosity = 'Normal'
$pester = Invoke-Pester -Configuration $cfg
if ($pester.FailedCount -gt 0) {
    throw "$($pester.FailedCount) Pester test(s) failed."
}
'    passed: {0} / {1}' -f $pester.PassedCount, $pester.TotalCount | Write-Host

# ---- 4. Stage ------------------------------------------------------------
Write-Step "Staging module copy at $StagePath"
if (Test-Path -LiteralPath $StagePath) {
    Remove-Item -LiteralPath $StagePath -Recurse -Force
}
$staged = New-Item -ItemType Directory -Path (Join-Path $StagePath 'IstioAmbientPreflight') -Force
Copy-Item -Path (Join-Path $modulePath '*') -Destination $staged.FullName -Recurse
$stagedFiles = @(Get-ChildItem -LiteralPath $staged.FullName -Recurse -File)
'    {0} files copied:' -f $stagedFiles.Count | Write-Host
$stagedFiles | ForEach-Object {
    '      ' + ($_.FullName.Substring($staged.FullName.Length + 1)) | Write-Host
}

# ---- 5. Publish summary --------------------------------------------------
Write-Step 'Publish step (manual)'
@"
Dry run complete. Module staged at:
  $($staged.FullName)

To actually publish to PowerShell Gallery, set your API key and run:

  `$env:PSGALLERY_API_KEY = '<your-psgallery-api-key>'
  Publish-Module ``
    -Path '$($staged.FullName)' ``
    -NuGetApiKey `$env:PSGALLERY_API_KEY ``
    -Repository PSGallery

Reference: https://learn.microsoft.com/powershell/gallery/how-to/publishing-packages/publishing-a-package
See RELEASING.md in this repository for the full release runbook.
"@ | Write-Host
