function Invoke-Kubectl {
    <#
    .SYNOPSIS
        Runs kubectl and returns parsed JSON output.

    .DESCRIPTION
        Thin wrapper around the kubectl binary. This is the single seam between
        the module and kubectl: all cluster access in IstioAmbientPreflight flows
        through here, so tests can mock cluster responses by mocking this one
        function.

        Behavior:
        - Prepends '--context <name>' when -Context is supplied.
        - Captures stdout and stderr separately. A non-zero exit code raises a
          terminating error that includes the command line, exit code, and the
          trimmed stderr output.
        - Parses stdout as JSON by default. Callers should therefore include
          '-o', 'json' in -Arguments. Use -Raw to return the stdout string
          unchanged (for commands like 'version --client' that do not emit JSON).

    .PARAMETER Context
        Name of the kubectl context to target. When omitted, kubectl uses the
        current-context from kubeconfig.

    .PARAMETER Arguments
        Arguments passed verbatim to kubectl. Do NOT include '--context' here;
        it is added automatically when -Context is supplied.

    .PARAMETER Raw
        Return the raw stdout string instead of parsing it as JSON.

    .EXAMPLE
        PS> Invoke-Kubectl -Context my-cluster -Arguments @('get', 'namespaces', '-o', 'json')

        Returns the parsed JSON object listing namespaces in the 'my-cluster'
        context.

    .EXAMPLE
        PS> Invoke-Kubectl -Arguments @('version', '--client', '--short') -Raw

        Returns the raw stdout from `kubectl version --client --short`.

    .OUTPUTS
        System.Management.Automation.PSCustomObject (parsed JSON) or System.String
        when -Raw is specified.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Context,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Arguments,

        [Parameter()]
        [switch]$Raw
    )

    $kubectl = Get-Command -Name 'kubectl' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $kubectl) {
        throw "kubectl was not found on PATH. Install kubectl (https://kubernetes.io/docs/tasks/tools/) and ensure it is on PATH before running IstioAmbientPreflight."
    }

    $fullArgs = [System.Collections.Generic.List[string]]::new()
    if ($PSBoundParameters.ContainsKey('Context') -and -not [string]::IsNullOrWhiteSpace($Context)) {
        $fullArgs.Add('--context')
        $fullArgs.Add($Context)
    }
    foreach ($arg in $Arguments) {
        $fullArgs.Add([string]$arg)
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = $kubectl.Source
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    foreach ($arg in $fullArgs) {
        $psi.ArgumentList.Add($arg)
    }

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi

    $stdout   = ''
    $stderr   = ''
    $exitCode = -1
    try {
        [void]$proc.Start()
        # Read both streams concurrently to avoid a deadlock when either buffer fills.
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $proc.WaitForExit()
        $stdout   = $stdoutTask.GetAwaiter().GetResult()
        $stderr   = $stderrTask.GetAwaiter().GetResult()
        $exitCode = $proc.ExitCode
    } catch {
        throw "Failed to invoke kubectl ('$($kubectl.Source)'): $($_.Exception.Message)"
    } finally {
        $proc.Dispose()
    }

    $renderedCmd = 'kubectl ' + ($fullArgs -join ' ')

    if ($exitCode -ne 0) {
        $trimmed = if ($stderr) { $stderr.Trim() } else { '<no stderr output>' }
        throw "kubectl exited with code $exitCode. Command: $renderedCmd`nStderr: $trimmed"
    }

    if ($Raw) {
        return $stdout
    }

    if ([string]::IsNullOrWhiteSpace($stdout)) {
        throw "kubectl returned empty output. Expected JSON. Did you include '-o json' in -Arguments? Command: $renderedCmd"
    }

    try {
        return $stdout | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse kubectl output as JSON. Command: $renderedCmd`nParse error: $($_.Exception.Message)"
    }
}
