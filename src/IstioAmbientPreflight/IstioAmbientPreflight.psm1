Set-StrictMode -Version Latest

$moduleRoot = $PSScriptRoot

$privatePath = Join-Path -Path $moduleRoot -ChildPath 'Private'
$publicPath  = Join-Path -Path $moduleRoot -ChildPath 'Public'

$privateScripts = if (Test-Path -LiteralPath $privatePath) {
    @(Get-ChildItem -Path $privatePath -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
} else {
    @()
}

$publicScripts = if (Test-Path -LiteralPath $publicPath) {
    @(Get-ChildItem -Path $publicPath -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
} else {
    @()
}

foreach ($script in @($privateScripts) + @($publicScripts)) {
    try {
        . $script.FullName
    } catch {
        throw "Failed to dot-source '$($script.FullName)': $($_.Exception.Message)"
    }
}

if ($publicScripts.Count -gt 0) {
    Export-ModuleMember -Function $publicScripts.BaseName
}
