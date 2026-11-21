# Changelog

All notable changes to `istio-ambient-preflight` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **G-01** (Blocker, Ingress) in new `Test-GatewayConflict`: flags each
  pair of an Istio Gateway (`networking.istio.io`) and a Gateway API
  Gateway (`gateway.networking.k8s.io`) that claim overlapping
  hostnames. Handles the Istio `namespace/` host prefix, `*` and
  `*.domain` wildcards, and Gateway API listeners without a hostname
  (which match every host). Ignores waypoint and east-west Gateway API
  Gateways (`istio-waypoint` / `istio-east-west` classes, `HBONE`
  listeners), since those are mesh infrastructure rather than ingress.
- **G-02** (Warning, Ingress) in `Test-GatewayConflict`: flags
  VirtualServices whose `spec.gateways` or `spec.http[].match[].gateways`
  name an Istio Gateway that does not exist. Resolves unqualified names
  in the VirtualService's own namespace, plus `<ns>/<name>` and the
  legacy `<name>.<ns>.svc.cluster.local` forms, and skips `mesh`. When the
  name matches a Gateway API Gateway, the message explains that a
  VirtualService cannot bind to it and suggests an HTTPRoute.
- `Invoke-AmbientPreflight` runs `Test-GatewayConflict` and passes
  `-Namespace` through to it.
- Integration fixture `tests/Integration/fixtures/gateways.yaml`
  exercising G-01, G-02 and a `mesh`-only negative control.
  `setup-fixtures.sh` installs the Istio 1.24.2 and Gateway API v1.2.1
  CRDs only when they are missing.
- 24 new unit tests (102 total).

### Fixed

- `Get-ClusterInventory` queried the non-existent resource type
  `gateways.gateway.networking.istio.io` instead of
  `gateways.networking.istio.io`. The error was treated as "CRD not
  installed", so the inventory always reported zero Istio Gateways.

### Changed

- `examples/sample-report.md` regenerated from the fixture cluster
  (now 4 Blockers, 2 Warnings, 2 Info).

## [0.1.0] - 2026-04-27

First public release. A read-only PowerShell module that scans a
Kubernetes cluster and produces a markdown readiness report for an
Istio sidecar-to-ambient migration.

### Added — module foundation

- Module scaffold: manifest, root module, Public/Private layout, MIT
  license. `Install-Module IstioAmbientPreflight` lands a working module.
- `Invoke-Kubectl` private helper: context-aware kubectl wrapper with
  separate stdout/stderr capture and JSON parsing. Single seam between
  the module and the CLI binary.
- `Get-ClusterInventory` private helper: single-pass inventory across
  Namespaces, Pods, Istio Gateways / VirtualServices / DestinationRules,
  Cilium NetworkPolicies, and Gateway API Gateways. Gracefully returns
  empty arrays when optional CRDs (Istio, Cilium, Gateway API) are not
  installed.
- `Format-Finding` private helper: canonical finding object factory
  emitting `IstioAmbientPreflight.Finding` PSCustomObjects with
  Severity / Category / CheckId / Resource / Message / DocLink.
- `New-AmbientMigrationReport` public cmdlet: renders findings to a
  markdown report with a readiness verdict (Ready / Ready with Warnings
  / Blocked), a severity-count summary table, and three always-emitted
  sections (Blockers / Warnings / Info).
- `Invoke-AmbientPreflight` public cmdlet: top-level orchestrator.
  Parameters `-Context`, `-OutputPath`, `-Namespace`,
  `-ExcludeNamespace`. Returns a result object with the report path
  and per-severity finding counts.
- Module manifest declares `FunctionsToExport` explicitly for
  `Invoke-AmbientPreflight` and `New-AmbientMigrationReport`.

### Added — checks

- **N-01** (Warning, Labels) in `Test-NamespaceLabels`: flags namespaces
  missing `istio.io/dataplane-mode=ambient` and not explicitly opted out
  with `=none`. System namespaces are skipped.
- **N-02** (Blocker, Labels) in `Test-NamespaceLabels`: flags
  namespaces labeled with BOTH `istio-injection=enabled` and
  `istio.io/dataplane-mode=ambient`. Honors `-ExcludeNamespace` and
  preempts N-01 for the same namespace.
- **P-01** (Info, Pods) in `Test-PodLabels`: flags pods labeled
  `istio.io/dataplane-mode=none` inside an ambient-enrolled namespace.
  Surfaces explicit opt-outs so they stay intentional.
- **P-02** (Info, Pods) in `Test-PodLabels`: flags pods in ambient
  namespaces that still carry sidecar-injection configuration
  (`sidecar.istio.io/inject=true` annotation on the pod, or
  `istio-injection=enabled` label on the namespace). Both reasons are
  rolled into a single per-pod finding when both apply.
- **C-01** (Blocker, Network) in `Test-CiliumPolicyCompatibility`:
  flags policies in ambient namespaces whose `fromEndpoints` rules
  restrict source by pod-selector matchLabels (e.g. `app=frontend`)
  without referencing a waypoint identity
  (`istio.io/gateway-name` or `istio.io/waypoint-for`). Suppresses when
  the policy already includes at least one waypoint-aware
  `fromEndpoints`, signalling the operator considered ambient.
- **C-02** (Blocker, Network) in `Test-CiliumPolicyCompatibility`:
  flags any CiliumNetworkPolicy in an ambient-enrolled namespace whose
  ingress rules do not admit ztunnel HBONE traffic on TCP port 15008.
  Policies in non-ambient namespaces and egress-only policies are
  ignored.
- C-01 and C-02 both fire on the same policy when both conditions
  apply (no mutual suppression).
- `Test-CiliumPolicyCompatibility` and `Test-PodLabels` no-op silently
  when their underlying CRDs / resource lists are empty.

### Added — testing and CI

- Pester 5 unit test harness: 78 tests covering Format-Finding,
  Invoke-Kubectl, Get-ClusterInventory, Test-NamespaceLabels,
  Test-CiliumPolicyCompatibility, Test-PodLabels,
  New-AmbientMigrationReport, and Invoke-AmbientPreflight.
- `tests/Unit/Helpers/` — checked-in kubectl stubs:
  `kubectl-stub.sh` for Linux/macOS plus a `kubectl-stub.cmd` +
  `kubectl-stub.ps1` pair for Windows. Both follow the same env-var
  contract (`IAP_STUB_STDOUT`, `IAP_STUB_STDERR`, `IAP_STUB_EXIT`,
  `IAP_STUB_ARGS_FILE`), so the Invoke-Kubectl test suite runs
  identically on every supported platform.
- Integration smoke test under `tests/Integration/` that runs
  `Invoke-AmbientPreflight` against the current kubectl context.
  Runtime-skipped when kubectl or a live cluster is unavailable.
- `tests/Integration/fixtures/` — kind-cluster recipe plus YAML for
  three namespaces (`payments`, `legacy-injection`, `unlabeled-app`),
  two pods (`opt-out-pod`, `legacy-pod`), and two
  CiliumNetworkPolicies (a triggering one and a clean negative
  control). Together they exercise N-01, N-02, P-01, P-02, C-01, and
  C-02 in a single run.
- `tests/Integration/fixtures/setup-fixtures.sh` and
  `teardown-fixtures.sh` — idempotent scripts that install the
  pinned Cilium CNP CRD and apply / remove the fixtures.
- GitHub Actions CI workflow: PSScriptAnalyzer lint + Pester unit
  tests on a matrix of `ubuntu-latest` and `windows-latest`.

### Added — release tooling and docs

- `build/Publish-Module.ps1` — pre-publish dry-run that validates the
  manifest, runs PSScriptAnalyzer, runs the Pester unit suite, and
  stages a publish-ready copy of the module under `.stage/`. Does
  not actually upload.
- `RELEASING.md` — end-to-end release runbook (version bump,
  changelog cut, dry run, manual `Publish-Module`, tag, GitHub
  release, post-publish smoke test).
- `docs/demo-script.md` — repeatable recipe for re-recording the
  README's screencast.
- `docs/demo.gif` — placeholder graphic; replaced when the real
  screencast is recorded.
- `examples/sample-report.md` — real preflight output captured from
  the kind fixture cluster, exercising every check.
- Session conventions documented in CLAUDE.md: end every session
  with a commit, keep docs in sync as code changes, re-read the
  four context docs at the start of every fresh session.

[Unreleased]: https://github.com/ppatel1604/istio-ambient-preflight/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ppatel1604/istio-ambient-preflight/releases/tag/v0.1.0
