# Roadmap

## v0.1.0 — Released 2026-04-27

**Goal:** A working tool that scans a cluster, runs 6+ checks, and
produces a useful markdown report. Shippable to PowerShell Gallery.

**Status:** released. See [`CHANGELOG.md`](./CHANGELOG.md) for the full
0.1.0 entry.

### Shipped checks

- [x] **N-01** Namespace missing `istio.io/dataplane-mode=ambient` label (Warning)
- [x] **N-02** Namespace has conflicting labels (both `istio-injection=enabled` and `istio.io/dataplane-mode=ambient`) (Blocker)
- [x] **P-01** Pods explicitly opted out via `istio.io/dataplane-mode=none` in ambient namespaces (Info)
- [x] **P-02** Pods in ambient namespaces still carrying sidecar-injection configuration (Info)
- [x] **C-01** Cilium NetworkPolicy using pod-selector `fromEndpoints` ingress that will fail with waypoint-routed traffic (Blocker)
- [x] **C-02** Cilium NetworkPolicy missing allowances for ztunnel traffic on port 15008 (Blocker)

### Shipped foundation + quality

- [x] Module scaffold + manifest, public/private layout
- [x] `Invoke-Kubectl`, `Get-ClusterInventory`, `Format-Finding`,
      `New-AmbientMigrationReport`, `Invoke-AmbientPreflight`
- [x] Pester unit tests for every Public and Private function (78 cases)
- [x] PSScriptAnalyzer clean against `./src`
- [x] GitHub Actions CI: lint + unit tests on Ubuntu **and** Windows
- [x] kind-based fixture set with idempotent setup/teardown scripts that
      exercise every shipped check end-to-end
- [x] `examples/sample-report.md` captured from the fixture cluster
- [x] `build/Publish-Module.ps1` dry-run + `RELEASING.md` runbook

### Carried forward

The following v0.1 stretch items are deferred to v0.2:

- [ ] Demo GIF / screencast in the README (placeholder in place; recipe
      lives at `docs/demo-script.md`)
- [ ] Wiring `tests/Integration/` into a CI integration job

## v0.2 — Patch generation, ingress checks, CI integration

**Goal:** Move from advisory to actionable, and round out the check
library on the ingress side.

### Checks to implement

- [x] **G-01** Istio Gateway and Gateway API Gateway claiming overlapping
      hostnames (Blocker) -- on `main`, unreleased
- [x] **G-02** VirtualServices bound to an Istio Gateway that doesn't
      exist (Warning) -- on `main`, unreleased
- [ ] Expanded check library (target ~15 total)

### Features

- [ ] `-GeneratePatches` flag on `Invoke-AmbientPreflight`
- [ ] Namespace label patches as kubectl-ready YAML
- [ ] ArgoCD-compatible Helm values diffs for common chart patterns
- [ ] `-OutputFormat json` for CI/CD pipeline integration
- [ ] Exit code semantics: 0 = ready, 1 = warnings, 2 = blockers
- [ ] Wire integration fixtures into a kind-based CI job

## v0.3 — Waypoint guidance

**Goal:** Help teams decide *where* to put waypoint proxies.

- [ ] Waypoint placement analysis (namespace vs. service-scoped)
- [ ] L7 policy migration guidance (AuthorizationPolicy conversions)
- [ ] Traffic path visualization in the report

## v1.0 — Production polish

- [ ] Multi-cluster scan mode
- [ ] HTML report output with filtering/sorting
- [ ] Plugin architecture so teams can add custom checks
- [ ] Documentation site (GitHub Pages)
- [ ] Case studies / real-world migration writeups

## Ideas Parking Lot (not committed)

- Support for other Istio modes (e.g. sidecar-to-sidecar upgrade validations)
- Linkerd compatibility checks
- Helm chart that deploys the tool as a cluster CronJob + report uploader
- Integration with Backstage as a scaffolder check
- `fix` subcommand that applies patches (would require careful trust design)
