# kubectl test stub (PowerShell). Mirrors kubectl-stub.sh: drives
# stdout / stderr / exit-code from environment variables and logs the
# argument vector to IAP_STUB_ARGS_FILE. Intended to be invoked via the
# kubectl-stub.cmd shim on Windows, but works as a stand-alone too.
#
# Using [Console]::Out.Write and [Console]::Error.Write avoids
# PowerShell adding a trailing newline that the bash variant does not.

if ($env:IAP_STUB_ARGS_FILE) {
    $line = ($args -join ' ')
    Add-Content -LiteralPath $env:IAP_STUB_ARGS_FILE -Value $line
}
if ($env:IAP_STUB_STDERR) {
    [Console]::Error.Write($env:IAP_STUB_STDERR)
}
if ($env:IAP_STUB_STDOUT) {
    [Console]::Out.Write($env:IAP_STUB_STDOUT)
}

$code = 0
if ($env:IAP_STUB_EXIT) {
    [void][int]::TryParse($env:IAP_STUB_EXIT, [ref]$code)
}
exit $code
