# CLAUDE.md — istio-ambient-preflight

This file gives Claude Code persistent context about this project. Read it before suggesting code or making changes.

## Project Purpose

`istio-ambient-preflight` is a PowerShell-first CLI tool that scans a Kubernetes cluster and produces a **readiness report** for migrating to Istio Ambient Mode. It flags the specific, silent problems that break ambient migrations: Cilium network policy incompatibilities, missing or conflicting dataplane-mode labels, ArgoCD sync issues, and Gateway API / Istio Gateway conflicts.

It is a free, open-source tool. It is also a portfolio piece and consulting lead generator for the author.

## Positioning & Audience

**Primary users:** Platform engineering and SRE teams at mid-to-large enterprises (50–5000 engineers) running Kubernetes with Istio, planning or executing a sidecar-to-ambient migration.

**Why PowerShell?** Most Kubernetes tooling is Go or Python. Microsoft-shop enterprises (a huge segment — banks, government, healthcare, traditional enterprises) have strong PowerShell familiarity and often prefer it for operational tooling. This is a deliberate market positioning choice, not an accident. A .NET Core library backend can be added later for heavier logic; PowerShell is the primary surface.

## Scope

### In scope for v0.1 (MVP)

- Scan a connected Kubernetes context (read-only, via `kubectl`)
- Inventory: namespaces, pods, Istio Gateways / VirtualServices / DestinationRules, Cilium NetworkPolicies, existing sidecars
- Ambient compatibility checks:
  - Namespaces missing the `istio.io/dataplane-mode=ambient` label
  - Pods explicitly opted out via `istio.io/dataplane-mode=none`
  - Cilium NetworkPolicies that don't account for ztunnel / waypoint traffic paths
  - Gateways that may conflict (Istio Gateway vs. Gateway API)
- Output: a markdown report (`./ambient-preflight-report.md`) with severity levels (Blocker / Warning / Info), plain-English explanations, and doc links
- Single-command invocation: `Invoke-AmbientPreflight -Context my-cluster`

### Out of scope for v0.1

- Modifying cluster state (read-only always, no exceptions in v0.1)
- Actual migration execution
- Multi-cluster scanning
- Waypoint proxy configuration generation
- Istio version upgrade recommendations
- A GUI / web dashboard
- Support for meshes other than Istio

### v0.2 candidates (not committed)

- `-GeneratePatches` flag: output ArgoCD-compatible Helm values diffs
- Waypoint proxy placement recommendations
- JSON output format for CI/CD integration
- HTML report output

## Technical Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Primary language | PowerShell 7+ (cross-platform) | Market positioning; underserved niche |
| Module structure | Standard PowerShell module (Public/Private pattern) | PSGallery-friendly |
| K8s access | Shell out to `kubectl` via wrapper function | Avoids K8s client lib dependency; works anywhere kubectl works |
| Serialization | `ConvertFrom-Json` on `kubectl -o json` output | Native, no deps |
| Testing | Pester 5.x | Standard for PowerShell |
| Integration tests | kind (Kubernetes-in-Docker) clusters in CI | Reproducible, fast |
| CI | GitHub Actions | Free for public repos |
| License | MIT | Maximum adoption; IP-clean |
| Distribution | PowerShell Gallery + GitHub Releases | Standard discoverability |

## Conventions

- Verb-Noun cmdlet names, approved PowerShell verbs only (`Get-Verb`)
- Public cmdlets in `src/IstioAmbientPreflight/Public/`, one file per cmdlet
- Private helpers in `src/IstioAmbientPreflight/Private/`
- Every public cmdlet has comment-based help (synopsis, description, parameters, example)
- Every check is a separate private function returning a structured finding object built via `Format-Finding`: `@{ Severity; Category; CheckId; Resource; Message; DocLink }` (PSTypeName `IstioAmbientPreflight.Finding`). A single private function may emit findings for multiple related CheckIds when they share one pass over the inventory (e.g. `Test-NamespaceLabels` emits both N-01 and N-02).
- No Write-Host for data output — use Write-Output / structured objects. Write-Host is fine for progress UI.
- No trailing whitespace, LF line endings, UTF-8 without BOM

## IP & Attribution Constraints

- All implementations must derive from **public documentation only**: istio.io, docs.cilium.io, argo-cd.readthedocs.io, kubernetes.io, gateway-api.sigs.k8s.io
- No references to any specific employer, internal platform, or proprietary patterns in code, comments, commits, docs, or examples
- Example cluster fixtures use generic names: `demo-app`, `payments-ns`, `frontend`, etc.
- If a specific Istio / Cilium interaction is documented in a public GitHub issue, CNCF Slack thread, or blog post, cite it in the check's `DocLink` field

## Repo Structure

```
istio-ambient-preflight/
├── README.md
├── LICENSE (MIT)
├── CHANGELOG.md
├── CLAUDE.md                          # this file
├── ROADMAP.md
├── CONTRIBUTING.md
├── src/
│   └── IstioAmbientPreflight/
│       ├── IstioAmbientPreflight.psd1 # module manifest
│       ├── IstioAmbientPreflight.psm1 # root module, dot-sources Public/Private
│       ├── Public/
│       │   ├── Invoke-AmbientPreflight.ps1
│       │   ├── Get-AmbientReadiness.ps1   # planned, not yet implemented
│       │   └── New-AmbientMigrationReport.ps1
│       └── Private/
│           ├── Invoke-Kubectl.ps1
│           ├── Get-ClusterInventory.ps1
│           ├── Test-NamespaceLabels.ps1
│           ├── Test-PodLabels.ps1
│           ├── Test-CiliumPolicyCompatibility.ps1
│           ├── Test-GatewayConflict.ps1
│           └── Format-Finding.ps1
├── tests/
│   ├── Unit/
│   │   └── *.Tests.ps1                # Pester tests with mocked kubectl
│   └── Integration/
│       ├── kind-cluster.yaml
│       └── *.Integration.Tests.ps1
├── examples/
│   ├── sample-report.md
│   └── demo-cluster/                  # generic kind cluster fixture
└── .github/
    └── workflows/
        ├── ci.yml                     # lint + unit tests on push
        └── integration.yml            # kind fixture integration tests on PR
```

## Definition of Done for v0.1

- [ ] `Install-Module IstioAmbientPreflight` works from PowerShell Gallery
- [ ] `Invoke-AmbientPreflight -Context <ctx>` runs end-to-end on a kind cluster with Istio installed and produces a readable markdown report
- [ ] At least 6 distinct checks implemented, each with doc links
- [ ] Pester unit test coverage ≥ 70% of Public + Private functions
- [ ] CI runs lint (PSScriptAnalyzer) + unit tests on every push, integration on PR
- [ ] README has: problem statement, demo GIF or screenshot, quick start, example output, roadmap, contact
- [ ] Sample report in `examples/` is convincing and shows what "good output" looks like

## Build Order (Suggested)

**Current status (2026-04-27):** v0.1.0 has been cut. All six v0.1
checks are shipped (N-01, N-02, P-01, P-02, C-01, C-02), the kind
fixture set with idempotent setup/teardown scripts exercises every
check end-to-end, `examples/sample-report.md` captures a real run,
unit tests run on both Ubuntu and Windows in CI, and `build/Publish-Module.ps1`
+ `RELEASING.md` document the manual publish flow. Carried forward to
v0.2: the demo GIF (placeholder + recording recipe in place at
`docs/demo.gif` and `docs/demo-script.md`), wiring the integration
fixtures into a CI job, and the **G-01** / **G-02** ingress checks.

**Update (2026-11-22):** G-01 and G-02 are implemented on `main`
(unreleased) in `Test-GatewayConflict`, with kind fixtures in
`tests/Integration/fixtures/gateways.yaml`. The same change fixed the
Istio Gateway CRD name in `Get-ClusterInventory`
(`gateways.networking.istio.io`), which had made every cluster look
like it had zero Istio Gateways. The fixture setup script installs
Istio and Gateway API CRDs only when they are missing, and teardown
never removes them, because they may belong to a real install.
The kind fixture integration job (`.github/workflows/integration.yml`)
runs on every PR to `main` and on demand, asserting each check's exact
findings via `tests/Integration/Fixtures.Integration.Tests.ps1`
(opt-in with `IAP_FIXTURE_CLUSTER=1`). When adding a check, add a
fixture to `tests/Integration/fixtures/` and a row to that test.
Remaining v0.2 items: demo GIF, JSON output, exit codes,
`-GeneratePatches`.

1. Repo scaffold: license, readme skeleton, module manifest, directory structure, .gitignore, GitHub Actions stub
2. `Invoke-Kubectl` wrapper + `Get-ClusterInventory` — foundation
3. First check: `Test-NamespaceLabels` + `Format-Finding` — proves the pattern
4. Markdown report generator (`New-AmbientMigrationReport`)
5. Wire up `Invoke-AmbientPreflight` as the public entry point
6. Add remaining checks one at a time, each with tests
7. Integration test against a real kind cluster
8. Polish README, record demo GIF
9. Tag v0.1.0, publish to PS Gallery

## Do Not Do

- Do not add Azure-specific or GCP-specific logic in v0.1. Cloud-agnostic only.
- Do not add authentication flows or secrets handling. The tool runs with the user's existing kubeconfig.
- Do not rebrand as a migration *executor*. v0.1 is read-only advisory. This is a deliberate trust / safety boundary.
- Do not copy code from any proprietary codebase. If unsure, rewrite from the public docs.

## Contact & Strategy

The README should direct interested users to the author's LinkedIn for consulting inquiries. The tool is the top of the funnel; consulting engagements are the monetization.

## Session conventions

- End every session with a git commit. Commit message should reference
  what was shipped (e.g. "feat: add N-02 conflicting labels check" or
  "docs: sync README/ROADMAP with implemented checks").
- At the end of every session that changes code, ensure README.md,
  ROADMAP.md, CHANGELOG.md (Unreleased), and CLAUDE.md (if conventions
  shifted) are in sync with the new state. Do not wait for an explicit
  "docs sync" session.
- Before starting work in a fresh session, read CLAUDE.md, ROADMAP.md,
  CHANGELOG.md, README.md to orient.