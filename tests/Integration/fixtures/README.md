# Integration fixtures

YAML and helper scripts for standing up a local cluster that exercises
every check the tool implements today. The goal is "stand it up,
copy/paste, see findings" -- both for local development and as the
the recipe the CI integration job (`.github/workflows/integration.yml`)
runs on every pull request.

## What each fixture demonstrates

| Fixture | Resource | Triggers |
|---|---|---|
| `namespaces.yaml` -> `unlabeled-app` (no `dataplane-mode` label) | Namespace | **N-01** (Warning) |
| `namespaces.yaml` -> `legacy-injection` (both `istio-injection=enabled` and `istio.io/dataplane-mode=ambient`) | Namespace | **N-02** (Blocker) |
| `pods.yaml` -> `payments/opt-out-pod` (`istio.io/dataplane-mode=none` in ambient namespace) | Pod | **P-01** (Info) |
| `pods.yaml` -> `legacy-injection/legacy-pod` (carries `sidecar.istio.io/inject=true` annotation) | Pod | **P-02** (Info) |
| `ciliumnetworkpolicy-missing-15008.yaml` -> `payments/pod-only-no-15008` | CiliumNetworkPolicy | **C-01** (Blocker) and **C-02** (Blocker) |
| `ciliumnetworkpolicy-waypoint-allowed.yaml` -> `payments/waypoint-allowed` (negative control) | CiliumNetworkPolicy | (nothing -- proves the checks don't false-positive) |
| `gateways.yaml` -> `payments/shop-legacy` (Istio) + `payments/shop-gw` (Gateway API), both claiming `shop.example.com` | Gateway | **G-01** (Blocker) |
| `gateways.yaml` -> `payments/shop-routes` (binds to missing `retired-gateway`) | VirtualService | **G-02** (Warning) |
| `gateways.yaml` -> `payments/internal-routes` (binds only to `mesh`; negative control) | VirtualService | (nothing) |

## Prerequisites

- `kubectl` on PATH, pointed at any cluster you have write access to
- For the kind path specifically: `kind` and a Docker-compatible runtime
- Internet access (to fetch the pinned Cilium, Istio and Gateway API CRDs)

You do **not** need a full Cilium or Istio installation -- the setup
script only installs the CRDs so kubectl will accept the resource
shapes. There is no Cilium agent, no Istio control plane, no CNI
override. The Istio and Gateway API CRDs are installed **only if they
are missing**, so an existing Istio install's CRDs are never overwritten,
and teardown never removes them.

## Stand it up

```bash
# Optional: spin up a fresh kind cluster.
kind create cluster --config tests/Integration/fixtures/kind-cluster.yaml

# Apply the fixture set (idempotent).
./tests/Integration/fixtures/setup-fixtures.sh
```

Then run the preflight:

```powershell
Import-Module ./src/IstioAmbientPreflight/IstioAmbientPreflight.psd1 -Force
Invoke-AmbientPreflight `
  -ExcludeNamespace local-path-storage,default `
  -OutputPath ./examples/sample-report.md
```

Expected: at least four Blockers (N-02 on `legacy-injection`, C-01 +
C-02 on `payments/pod-only-no-15008`, G-01 on the `shop-legacy` /
`shop-gw` pair), two Warnings (N-01 on `unlabeled-app`, G-02 on
`payments/shop-routes`), and two Info findings (P-01 + P-02). Exact
totals vary depending on what other namespaces your cluster carries
(kind also creates `local-path-storage`, and leaves `default`
unlabeled, so add `default` to `-ExcludeNamespace` to match
`examples/sample-report.md`).

## Tear it down

```bash
# Default: remove just the fixture namespaces (cascades pods + CNPs).
./tests/Integration/fixtures/teardown-fixtures.sh

# --full: also remove the Cilium CNP CRD.
./tests/Integration/fixtures/teardown-fixtures.sh --full

# Or delete the kind cluster entirely.
kind delete cluster --name ambient-preflight-fixture
```

## Why these fixtures live here

The CI integration job uses these same files, and
`tests/Integration/Fixtures.Integration.Tests.ps1` asserts the exact
finding each fixture should produce. Local runs and CI therefore share
one definition of "a cluster that exercises every check". When you add
a check, add its fixture here and a row to that test.

To run the fixture assertions locally after `setup-fixtures.sh`:

```powershell
$env:IAP_FIXTURE_CLUSTER = '1'
Invoke-Pester ./tests/Integration
```
