# Integration fixtures

YAML for standing up a local [kind](https://kind.sigs.k8s.io/) cluster
that reliably triggers every check implemented in this repo today:

| Fixture | Triggers |
|---|---|
| `namespaces.yaml` — `legacy` (no dataplane-mode label) | **N-01** (Warning) |
| `namespaces.yaml` — `half-migrated` (both `istio-injection=enabled` and `istio.io/dataplane-mode=ambient`) | **N-02** (Blocker) |
| `ciliumnetworkpolicy-missing-15008.yaml` in ambient-labeled `demo-app` | **C-02** (Blocker) |

These are **not** applied automatically by CI yet — running them requires
a kind cluster with Cilium installed for the CRDs, which is a larger
piece of setup. The goal here is just to make the "stand it up locally
and see the tool fire" path a single copy-paste.

## Prerequisites

- `kind` on PATH
- `kubectl` on PATH
- `helm` on PATH (to install Cilium)
- Docker or another kind-compatible container runtime

## Stand up the fixture cluster

From the repository root:

```bash
# 1. Create the kind cluster (CNI disabled so Cilium can own it).
kind create cluster --config tests/Integration/fixtures/kind-cluster.yaml

# 2. Install Cilium (pins a recent stable release; bump as needed).
helm repo add cilium https://helm.cilium.io/
helm repo update
helm install cilium cilium/cilium \
  --version 1.15.6 \
  --namespace kube-system \
  --set kubeProxyReplacement=false \
  --set operator.replicas=1

# 3. Wait for Cilium to become ready.
kubectl -n kube-system rollout status daemonset/cilium --timeout=300s

# 4. Apply the fixture namespaces and policy.
kubectl apply -f tests/Integration/fixtures/namespaces.yaml
kubectl apply -f tests/Integration/fixtures/ciliumnetworkpolicy-missing-15008.yaml
```

## Run the preflight against it

```powershell
Import-Module ./src/IstioAmbientPreflight/IstioAmbientPreflight.psd1 -Force
Invoke-AmbientPreflight `
  -Context (kubectl config current-context) `
  -ExcludeNamespace local-path-storage `
  -OutputPath ./ambient-preflight-report.md
```

Expected: at least two Blocker findings (one N-02 on `half-migrated`,
one C-02 on the `allow-frontend` policy in `demo-app`) and one Warning
finding (N-01 on `legacy`). The exact count depends on which other
namespaces kind and Cilium install create on your cluster.

## Tear it down

```bash
kind delete cluster --name ambient-preflight-fixture
```

## Why these fixtures live here

When the integration harness is wired into CI (see ROADMAP.md, v0.1
Quality section), it will consume these same files. Keeping them in
version control now gives local users — and the future CI job — a single
source of truth for what "a cluster that exercises every check" looks
like.
