# Roadmap

## v0.1 — MVP (target: 2 weekends of focused work)

**Goal:** A working tool that scans a cluster, runs 6+ checks, and produces a useful markdown report. Shippable to PowerShell Gallery.

### Completed

- [x] **N-01** Namespace missing `istio.io/dataplane-mode=ambient` label (Warning)
- [x] **N-02** Namespace has conflicting labels (both `istio-injection=enabled` and `istio.io/dataplane-mode=ambient`) (Blocker)
- [x] **P-01** Pods explicitly opted out via `istio.io/dataplane-mode=none` in ambient namespaces (Info)
- [x] **P-02** Pods in ambient namespaces still carrying sidecar-injection configuration (Info)
- [x] **C-01** Cilium NetworkPolicy using pod-selector `fromEndpoints` ingress that will fail with waypoint-routed traffic (Blocker)
- [x] **C-02** Cilium NetworkPolicy missing allowances for ztunnel traffic on port 15008 (Blocker)

### Checks to implement

- [ ] **G-01** Mixed Istio Gateway + Gateway API resources on overlapping hosts (Blocker)
- [ ] **G-02** VirtualServices referencing gateways that don't exist (Warning)

### Foundation

- [x] Module scaffold + manifest
- [x] `Invoke-Kubectl` wrapper (handles context, JSON parsing, error paths)
- [x] `Get-ClusterInventory` — single pass of cluster state, cached for all checks
- [x] `Format-Finding` — canonical finding object shape
- [x] `New-AmbientMigrationReport` — markdown writer with severity grouping
- [x] `Invoke-AmbientPreflight` — top-level orchestrator

### Quality

- [x] Pester unit tests for every Public and Private function
- [ ] Integration test harness: `kind` cluster with Istio ambient, Cilium, and a sample app
- [x] GitHub Actions CI: PSScriptAnalyzer lint + Pester unit tests on every push and PR
- [ ] PSScriptAnalyzer passes with zero warnings

### Launch artifacts

- [x] `examples/demo-cluster/sample-report.md` — realistic example output
- [ ] Demo GIF or short screencast in the README
- [ ] `CHANGELOG.md` with v0.1.0 entry
- [ ] PowerShell Gallery publish
- [ ] GitHub release with tag `v0.1.0`

## v0.2 — Patch generation and CI integration

**Goal:** Move from advisory to actionable. Generate the specific YAML patches teams need.

- [ ] `-GeneratePatches` flag on `Invoke-AmbientPreflight`
- [ ] Namespace label patches as kubectl-ready YAML
- [ ] ArgoCD-compatible Helm values diffs for common chart patterns
- [ ] `-OutputFormat json` for CI/CD pipeline integration
- [ ] Exit code semantics: 0 = ready, 1 = warnings, 2 = blockers
- [ ] Expanded check library (aim for ~15 total)

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
