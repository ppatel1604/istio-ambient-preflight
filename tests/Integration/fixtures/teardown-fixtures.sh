#!/usr/bin/env bash
# Reverse setup-fixtures.sh.
#
# Default mode deletes the three fixture namespaces, which cascade-deletes
# pods and CiliumNetworkPolicies in those namespaces. The Cilium CNP CRD
# itself is left installed because re-installing it on each iteration is
# slow; pass --full to also remove the CRD.
#
# Idempotent: missing resources are not errors.

set -euo pipefail

FULL=0
for arg in "$@"; do
  case "$arg" in
    --full) FULL=1 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--full]"
      echo "  --full   Also remove the Cilium CNP CRD (slow to reinstall)"
      exit 0
      ;;
    *)
      echo "Unknown arg: $arg" >&2
      exit 2
      ;;
  esac
done

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is not on PATH." >&2
  exit 1
fi

ctx=$(kubectl config current-context 2>/dev/null || echo '<none>')
echo "==> Target context: ${ctx}"

echo "==> Deleting fixture namespaces (cascades pods + CNPs)..."
kubectl delete namespace payments legacy-injection unlabeled-app \
  --ignore-not-found=true --wait=false

if [ "$FULL" -eq 1 ]; then
  echo "==> Removing Cilium CNP CRD..."
  kubectl delete crd ciliumnetworkpolicies.cilium.io --ignore-not-found=true
else
  echo "==> Cilium CNP CRD left installed (rerun with --full to remove)."
fi

echo "==> Done."
