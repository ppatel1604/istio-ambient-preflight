#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# These tests execute the real Invoke-Kubectl code path by planting a stub
# 'kubectl' on PATH. The stub is a POSIX shell script, so the suite runs on
# Linux and macOS (including the Ubuntu CI runner). Windows is skipped; a
# .cmd-based stub can be added when a Windows CI leg is introduced.

BeforeAll {
    $privateRoot = Resolve-Path "$PSScriptRoot/../../src/IstioAmbientPreflight/Private"
    . (Join-Path $privateRoot 'Invoke-Kubectl.ps1')

    $script:origPath = $env:PATH
    $script:stubRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("iap-kubectl-stub-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:stubRoot | Out-Null

    $script:argsFile = Join-Path $script:stubRoot 'invocations.log'

    $stubPath = Join-Path $script:stubRoot 'kubectl'
    $stubBody = @'
#!/usr/bin/env bash
if [ -n "$IAP_STUB_ARGS_FILE" ]; then
  printf '%s\n' "$*" >> "$IAP_STUB_ARGS_FILE"
fi
if [ -n "$IAP_STUB_STDERR" ]; then
  printf '%s' "$IAP_STUB_STDERR" >&2
fi
if [ -n "$IAP_STUB_STDOUT" ]; then
  printf '%s' "$IAP_STUB_STDOUT"
fi
exit "${IAP_STUB_EXIT:-0}"
'@
    # Write with LF endings regardless of host to keep the shebang valid.
    [System.IO.File]::WriteAllText($stubPath, $stubBody.Replace("`r`n", "`n"))
    & /bin/chmod '+x' $stubPath

    $env:PATH            = $script:stubRoot + [System.IO.Path]::PathSeparator + $script:origPath
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

Describe 'Invoke-Kubectl' -Skip:($IsWindows) {

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
