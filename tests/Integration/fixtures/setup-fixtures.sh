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
#
# Idempotent: re-running is safe; kubectl apply does the right thing.
#
# Cilium CRDs are sourced from a pinned upstream release tarball:
#   pinned: cilium v1.16.5
#     https://github.com/cilium/cilium/releases/tag/v1.16.5
# The CRD itself is at:
#   https://raw.githubusercontent.com/cilium/cilium/v1.16.5/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumnetworkpolicies.yaml
# Bump the version at the top of this script when refreshing.

set -euo pipefail

CILIUM_VERSION="v1.16.5"
CILIUM_CNP_CRD_URL="https://raw.githubusercontent.com/cilium/cilium/${CILIUM_VERSION}/pkg/k8s/apis/cilium.io/client/crds/v2/ciliumnetworkpolicies.yaml"

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

cat <<'EOF'

==> Done.

Run the preflight to see findings:

  pwsh -NoProfile -Command "
    Import-Module ./src/IstioAmbientPreflight/IstioAmbientPreflight.psd1 -Force
    Invoke-AmbientPreflight -ExcludeNamespace local-path-storage -OutputPath ./examples/sample-report.md
  "

Tear down with: ./tests/Integration/fixtures/teardown-fixtures.sh
EOF
