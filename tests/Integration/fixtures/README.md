# Integration fixtures

YAML and helper scripts for standing up a local cluster that exercises
every check the tool implements today. The goal is "stand it up,
copy/paste, see findings" -- both for local development and as the
reference recipe for the future CI integration job.

## What each fixture demonstrates

| Fixture | Resource | Triggers |
|---|---|---|
| `namespaces.yaml` -> `unlabeled-app` (no `dataplane-mode` label) | Namespace | **N-01** (Warning) |
| `namespaces.yaml` -> `legacy-injection` (both `istio-injection=enabled` and `istio.io/dataplane-mode=ambient`) | Namespace | **N-02** (Blocker) |
| `pods.yaml` -> `payments/opt-out-pod` (`istio.io/dataplane-mode=none` in ambient namespace) | Pod | **P-01** (Info) |
| `pods.yaml` -> `legacy-injection/legacy-pod` (carries `sidecar.istio.io/inject=true` annotation) | Pod | **P-02** (Info) |
| `ciliumnetworkpolicy-missing-15008.yaml` -> `payments/pod-only-no-15008` | CiliumNetworkPolicy | **C-01** (Blocker) and **C-02** (Blocker) |
| `ciliumnetworkpolicy-waypoint-allowed.yaml` -> `payments/waypoint-allowed` (negative control) | CiliumNetworkPolicy | (nothing -- proves the checks don't false-positive) |

## Prerequisites

- `kubectl` on PATH, pointed at any cluster you have write access to
- For the kind path specifically: `kind` and a Docker-compatible runtime
- Internet access (to fetch the pinned Cilium CRD)

You do **not** need a full Cilium installation -- the setup script only
installs the CiliumNetworkPolicy CRD so kubectl will accept the resource
shape. There is no Cilium agent, no CNI override, nothing else.

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
  -ExcludeNamespace local-path-storage `
  -OutputPath ./examples/sample-report.md
```

Expected: at least three Blockers (N-02 on `legacy-injection`, C-01 +
C-02 on `payments/pod-only-no-15008`), one Warning (N-01 on
`unlabeled-app`), and two Info findings (P-01 + P-02). Exact totals
vary depending on what other namespaces your cluster carries (kind
also creates `local-path-storage`, etc.).

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

When the integration harness is wired into CI (see ROADMAP.md), it will
consume these same files. Keeping them in version control now gives
local users -- and the future CI job -- a single source of truth for
what "a cluster that exercises every check" looks like.
