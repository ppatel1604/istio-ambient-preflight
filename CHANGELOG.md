# Changelog

All notable changes to `istio-ambient-preflight` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial module scaffold: manifest, root module, Public/Private layout.
- `Invoke-Kubectl` private helper: context-aware kubectl wrapper with JSON parsing.
- `Format-Finding` private helper: canonical finding object factory.
- `Get-ClusterInventory` private helper: single-pass cluster inventory across
  Namespaces, Pods, Istio Gateways / VirtualServices / DestinationRules,
  Cilium NetworkPolicies, and Gateway API Gateways. Gracefully returns empty
  arrays when optional CRDs (Istio, Cilium, Gateway API) are not installed.
- `Test-NamespaceLabels` private helper — **first real check (N-01)**:
  Warning for namespaces missing `istio.io/dataplane-mode=ambient` and not
  explicitly opted out with `...=none`. System namespaces are skipped.
- `Test-CiliumPolicyCompatibility` private helper — **check C-02**:
  Blocker for any CiliumNetworkPolicy in an ambient-enrolled namespace
  whose ingress rules do not admit ztunnel HBONE traffic on TCP port
  15008. Policies in non-ambient namespaces and egress-only policies are
  ignored. No-ops silently when the Cilium CRD is not installed.
- `-ExcludeNamespace` parameter on `Invoke-AmbientPreflight` and
  `Test-NamespaceLabels`: appends user-supplied names to the built-in
  system-namespace skip list (kube-system, kube-public, kube-node-lease,
  istio-system, cilium). Lets kind/AKS/EKS/GKE users suppress expected
  N-01 noise from infrastructure namespaces.
- `New-AmbientMigrationReport` public cmdlet: renders findings to a markdown
  report with a readiness verdict (Ready / Ready with Warnings / Blocked),
  a severity-count summary table, and three always-emitted sections
  (Blockers / Warnings / Info).
- `Invoke-AmbientPreflight` public cmdlet: top-level orchestrator.
  Parameters `-Context`, `-OutputPath`, `-Namespace`. Returns a result
  object containing the report path and severity counts.
- Module manifest now declares `FunctionsToExport` explicitly for
  `Invoke-AmbientPreflight` and `New-AmbientMigrationReport`.
- Pester 5 unit test harness with mocked kubectl (Format-Finding,
  Invoke-Kubectl, Get-ClusterInventory, Test-NamespaceLabels,
  New-AmbientMigrationReport).
- Integration smoke test under `tests/Integration/` that runs
  `Invoke-AmbientPreflight` against the current kubectl context.
  Runtime-skipped when kubectl or a live cluster is unavailable.
- GitHub Actions CI workflow: PSScriptAnalyzer lint + Pester unit tests on Ubuntu / PowerShell 7.

[Unreleased]: https://github.com/ppatel1604/istio-ambient-preflight/commits/main
