#!/usr/bin/env bash
# Stand up an enriched fixture set on the current kubectl context so that
# Invoke-AmbientPreflight has something to find. Designed for a local
# kind cluster but works against any cluster you can write to.
#
# What it does:
#   1. Installs the Cilium CiliumNetworkPolicy CRD only (NOT the Cilium
#      runtime). Just enough so that kubectl will accept the CNP
#      resources below; the CRD is harmless on clusters that don't have
#      Cilium running.
#   2. Creates 3 namespaces (payments, legacy-injection, unlabeled-app).
#   3. Creates 2 pods (opt-out-pod, legacy-pod) using pause:3.9.
#   4. Creates 2 CiliumNetworkPolicies (a triggering one and a clean
#      negative-control one).
#   5. Installs the Istio networking CRDs and the Gateway API standard
#      CRDs ONLY if they are not already present (so an existing Istio
#      install is never overwritten), then creates an Istio Gateway, a
#      Gateway API Gateway and two VirtualServices for G-01 / G-02.
#
# Idempotent: re-running is safe; kubectl apply does the right thing.
#
# Cilium CRDs are sourced from a pinned upstream release tarball:
#   pinned: cilium v1.16.5
#     https://github.com/cilium/cilium/releases/tag/v1.16.5
# The CRD itself is at:
#   https://raw.githubusercontent.com/cilium/cilium/v1.16.5/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumnetworkpolicies.yaml
#
# Istio and Gateway API CRDs (installed only when missing):
#   pinned: istio 1.24.2
#     https://raw.githubusercontent.com/istio/istio/1.24.2/manifests/charts/base/files/crd-all.gen.yaml
#   pinned: gateway-api v1.2.1
#     https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
# Bump the versions at the top of this script when refreshing.

set -euo pipefail

CILIUM_VERSION="v1.16.5"
CILIUM_CNP_CRD_URL="https://raw.githubusercontent.com/cilium/cilium/${CILIUM_VERSION}/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumnetworkpolicies.yaml"
ISTIO_VERSION="1.24.2"
ISTIO_CRDS_URL="https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/manifests/charts/base/files/crd-all.gen.yaml"
GATEWAY_API_VERSION="v1.2.1"
GATEWAY_API_CRDS_URL="https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is not on PATH." >&2
  exit 1
fi

ctx=$(kubectl config current-context 2>/dev/null || echo '<none>')
echo "==> Target context: ${ctx}"

echo "==> Installing Cilium CNP CRD (${CILIUM_VERSION})..."
kubectl apply -f "${CILIUM_CNP_CRD_URL}"

echo "==> Waiting for the CRD to become Established..."
kubectl wait --for=condition=Established crd/ciliumnetworkpolicies.cilium.io --timeout=60s

echo "==> Applying fixture namespaces..."
kubectl apply -f "${SCRIPT_DIR}/namespaces.yaml"

echo "==> Applying fixture pods..."
kubectl apply -f "${SCRIPT_DIR}/pods.yaml"

echo "==> Applying CiliumNetworkPolicy fixtures..."
kubectl apply -f "${SCRIPT_DIR}/ciliumnetworkpolicy-missing-15008.yaml"
kubectl apply -f "${SCRIPT_DIR}/ciliumnetworkpolicy-waypoint-allowed.yaml"

# Install a CRD bundle only when its marker CRD is absent. Never
# re-applies over an existing install (which may be a different version
# managed by istioctl, Helm or ArgoCD).
ensure_crds() {
  local marker="$1" url="$2" label="$3"
  if kubectl get crd "${marker}" >/dev/null 2>&1; then
    echo "==> ${label} CRDs already present (${marker}); leaving them untouched."
  else
    echo "==> Installing ${label} CRDs..."
    kubectl apply -f "${url}"
    kubectl wait --for=condition=Established "crd/${marker}" --timeout=60s
  fi
}

ensure_crds gateways.networking.istio.io        "${ISTIO_CRDS_URL}"       "Istio ${ISTIO_VERSION}"
ensure_crds virtualservices.networking.istio.io "${ISTIO_CRDS_URL}"       "Istio ${ISTIO_VERSION}"
ensure_crds gateways.gateway.networking.k8s.io  "${GATEWAY_API_CRDS_URL}" "Gateway API ${GATEWAY_API_VERSION}"

echo "==> Applying ingress (Gateway / VirtualService) fixtures..."
kubectl apply -f "${SCRIPT_DIR}/gateways.yaml"

cat <<'EOF'

==> Done.

Run the preflight to see findings:

  pwsh -NoProfile -Command "
    Import-Module ./src/IstioAmbientPreflight/IstioAmbientPreflight.psd1 -Force
    Invoke-AmbientPreflight -ExcludeNamespace local-path-storage,default -OutputPath ./examples/sample-report.md
  "

Tear down with: ./tests/Integration/fixtures/teardown-fixtures.sh
EOF
