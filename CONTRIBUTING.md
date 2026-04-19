# Contributing to istio-ambient-preflight

Thanks for your interest. This project aims to stay small, sharp, and useful
for platform teams planning an Istio sidecar-to-ambient migration.

## Ground rules

- All implementations must derive from **public documentation only**:
  [istio.io](https://istio.io/), [docs.cilium.io](https://docs.cilium.io/),
  [argo-cd.readthedocs.io](https://argo-cd.readthedocs.io/),
  [kubernetes.io](https://kubernetes.io/),
  [gateway-api.sigs.k8s.io](https://gateway-api.sigs.k8s.io/).
- No proprietary patterns, internal-platform references, or employer-specific
  code in comments, commits, examples, or tests.
- The tool is **read-only** in v0.1. No PRs that mutate cluster state.

## Development setup

Prerequisites:

- PowerShell 7.0 or later
- `kubectl` on your PATH
- [Pester](https://pester.dev/) 5.x — `Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser`
- [PSScriptAnalyzer](https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/overview) — `Install-Module PSScriptAnalyzer -Scope CurrentUser`

Run the tests:

```powershell
Invoke-Pester -Path ./tests/Unit
```

Run the linter:

```powershell
Invoke-ScriptAnalyzer -Path ./src -Recurse
```

## Adding a new check

Each ambient-compatibility check is a self-contained private function living
in `src/IstioAmbientPreflight/Private/Test-*.ps1`. A check:

1. Takes the cached cluster inventory as input.
2. Returns zero or more finding objects produced by `Format-Finding`.
3. Has a stable `CheckId` (e.g. `N-01`, `C-02`) and a `DocLink` to the
   authoritative public reference that justifies the check.
4. Has a Pester test in `tests/Unit/` with mocked inputs covering both the
   "finding emitted" and "clean" cases.

## Commit style

- Imperative, present tense: `Add Cilium waypoint ingress check`
- Reference the check ID in the subject when relevant: `C-02: flag policies missing ztunnel port 15008`

## Questions

Open an issue or reach out via LinkedIn — see the contact section in the README.
