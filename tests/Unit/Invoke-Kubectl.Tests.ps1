#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# These tests execute the real Invoke-Kubectl code path by planting a stub
# 'kubectl' on PATH. The stub binaries live under tests/Unit/Helpers/ and
# come in two flavors: a POSIX shell script for Linux/macOS, and a
# .cmd + .ps1 pair for Windows. Both share the same env-var contract:
#   IAP_STUB_ARGS_FILE  - if set, the args vector is appended (one line
#                         per invocation) so tests can assert on it.
#   IAP_STUB_STDOUT     - written verbatim to stdout.
#   IAP_STUB_STDERR     - written verbatim to stderr.
#   IAP_STUB_EXIT       - exit code (default 0).

BeforeAll {
    $privateRoot = Resolve-Path "$PSScriptRoot/../../src/IstioAmbientPreflight/Private"
    . (Join-Path $privateRoot 'Invoke-Kubectl.ps1')

    $helpersRoot = Resolve-Path "$PSScriptRoot/Helpers"

    $script:origPath = $env:PATH
    $script:stubRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iap-kubectl-stub-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:stubRoot | Out-Null

    $script:argsFile = Join-Path $script:stubRoot 'invocations.log'

    if ($IsWindows) {
        # The .cmd shim invokes pwsh against the sibling .ps1, so both
        # files must live next to each other in the stub directory.
        Copy-Item -LiteralPath (Join-Path $helpersRoot 'kubectl-stub.cmd') `
                  -Destination (Join-Path $script:stubRoot 'kubectl.cmd')
        Copy-Item -LiteralPath (Join-Path $helpersRoot 'kubectl-stub.ps1') `
                  -Destination (Join-Path $script:stubRoot 'kubectl-stub.ps1')
    } else {
        $stubDest = Join-Path $script:stubRoot 'kubectl'
        # Write through .NET to guarantee LF line endings; a CRLF shebang
        # would silently fail with /usr/bin/env: 'bash\r'.
        $stubBody = Get-Content -LiteralPath (Join-Path $helpersRoot 'kubectl-stub.sh') -Raw
        [System.IO.File]::WriteAllText($stubDest, $stubBody.Replace("`r`n", "`n"))
        & /bin/chmod '+x' $stubDest
    }

    $env:PATH               = $script:stubRoot + [System.IO.Path]::PathSeparator + $script:origPath
    $env:IAP_STUB_ARGS_FILE = $script:argsFile
}

AfterAll {
    $env:PATH = $script:origPath
    Remove-Item env:IAP_STUB_ARGS_FILE  -ErrorAction SilentlyContinue
    Remove-Item env:IAP_STUB_STDOUT     -ErrorAction SilentlyContinue
    Remove-Item env:IAP_STUB_STDERR     -ErrorAction SilentlyContinue
    Remove-Item env:IAP_STUB_EXIT       -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $script:stubRoot) {
        Remove-Item -LiteralPath $script:stubRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Invoke-Kubectl' {

    BeforeEach {
        if (Test-Path -LiteralPath $script:argsFile) {
            Remove-Item -LiteralPath $script:argsFile -Force
        }
        Remove-Item env:IAP_STUB_STDOUT -ErrorAction SilentlyContinue
        Remove-Item env:IAP_STUB_STDERR -ErrorAction SilentlyContinue
        Remove-Item env:IAP_STUB_EXIT   -ErrorAction SilentlyContinue
    }

    Context 'happy path' {

        It 'parses JSON stdout into an object by default' {
            $env:IAP_STUB_STDOUT = '{"kind":"NamespaceList","items":[{"metadata":{"name":"demo-app"}}]}'

            $result = Invoke-Kubectl -Arguments @('get', 'namespaces', '-o', 'json')

            $result.kind         | Should -Be 'NamespaceList'
            $result.items.Count  | Should -Be 1
            $result.items[0].metadata.name | Should -Be 'demo-app'
        }

        It 'returns raw stdout when -Raw is specified' {
            $env:IAP_STUB_STDOUT = "Client Version: v1.30.0`n"

            $result = Invoke-Kubectl -Arguments @('version', '--client', '--short') -Raw

            $result | Should -Match 'Client Version'
        }

        It 'prepends --context <name> when -Context is supplied' {
            $env:IAP_STUB_STDOUT = '{}'

            Invoke-Kubectl -Context 'my-cluster' -Arguments @('get', 'pods', '-o', 'json') | Out-Null

            $logged = Get-Content -LiteralPath $script:argsFile -Raw
            $logged.Trim() | Should -Be '--context my-cluster get pods -o json'
        }

        It 'omits --context when -Context is not supplied' {
            $env:IAP_STUB_STDOUT = '{}'

            Invoke-Kubectl -Arguments @('get', 'pods', '-o', 'json') | Out-Null

            $logged = Get-Content -LiteralPath $script:argsFile -Raw
            $logged.Trim() | Should -Be 'get pods -o json'
        }

        It 'omits --context when -Context is empty or whitespace' {
            $env:IAP_STUB_STDOUT = '{}'

            Invoke-Kubectl -Context '   ' -Arguments @('get', 'pods', '-o', 'json') | Out-Null

            $logged = Get-Content -LiteralPath $script:argsFile -Raw
            $logged.Trim() | Should -Be 'get pods -o json'
        }
    }

    Context 'error handling' {

        It 'throws including exit code and stderr when kubectl exits non-zero' {
            $env:IAP_STUB_EXIT   = '1'
            $env:IAP_STUB_STDERR = 'Error from server (Forbidden): namespaces is forbidden'

            {
                Invoke-Kubectl -Arguments @('get', 'namespaces', '-o', 'json')
            } | Should -Throw -ExpectedMessage '*exit*1*Forbidden*'
        }

        It 'throws when stdout is empty and -Raw was not requested' {
            $env:IAP_STUB_STDOUT = ''
            $env:IAP_STUB_EXIT   = '0'

            {
                Invoke-Kubectl -Arguments @('get', 'namespaces', '-o', 'json')
            } | Should -Throw -ExpectedMessage '*empty output*'
        }

        It 'throws with a parse-error message when stdout is not valid JSON' {
            $env:IAP_STUB_STDOUT = 'not { valid json'

            {
                Invoke-Kubectl -Arguments @('get', 'namespaces', '-o', 'json')
            } | Should -Throw -ExpectedMessage '*parse*JSON*'
        }
    }
}
