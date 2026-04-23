# Istio Ambient Preflight Report

**Generated:** 2026-04-22T14:10:03Z  
**Context:** demo-prod  
**Verdict:** Blocked

## Summary

| Severity | Count |
|---|---|
| 🔴 Blocker | 2 |
| 🟡 Warning | 3 |
| 🔵 Info | 0 |

## 🔴 Blockers

### C-02 · Network · CiliumNetworkPolicy/allow-frontend in namespace payments

CiliumNetworkPolicy 'allow-frontend' in ambient namespace 'payments' declares ingress rules but does not allow TCP port 15008. In ambient mode, mesh traffic arrives on the destination node via ztunnel using HBONE on TCP/15008; this policy will silently drop mesh traffic after migration. Add an ingress rule that permits TCP/15008 from the ztunnel DaemonSet (for example, select 'k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=istio-system' with toPorts port 15008), or migrate the L7 controls to an Istio AuthorizationPolicy.

**Reference:** https://istio.io/latest/docs/ambient/architecture/traffic-redirection/

### C-02 · Network · CiliumNetworkPolicy/checkout-ingress in namespace checkout

CiliumNetworkPolicy 'checkout-ingress' in ambient namespace 'checkout' declares ingress rules but does not allow TCP port 15008. In ambient mode, mesh traffic arrives on the destination node via ztunnel using HBONE on TCP/15008; this policy will silently drop mesh traffic after migration. Add an ingress rule that permits TCP/15008 from the ztunnel DaemonSet (for example, select 'k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=istio-system' with toPorts port 15008), or migrate the L7 controls to an Istio AuthorizationPolicy.

**Reference:** https://istio.io/latest/docs/ambient/architecture/traffic-redirection/

## 🟡 Warnings

### N-01 · Labels · Namespace/analytics

Namespace 'analytics' has no 'istio.io/dataplane-mode' label. Workloads here will not be enrolled in the ambient mesh after migration. Apply 'kubectl label namespace analytics istio.io/dataplane-mode=ambient' to enroll, or 'kubectl label namespace analytics istio.io/dataplane-mode=none' to explicitly opt out.

**Reference:** https://istio.io/latest/docs/ambient/usage/add-workloads/

### N-01 · Labels · Namespace/frontend

Namespace 'frontend' has no 'istio.io/dataplane-mode' label. Workloads here will not be enrolled in the ambient mesh after migration. Apply 'kubectl label namespace frontend istio.io/dataplane-mode=ambient' to enroll, or 'kubectl label namespace frontend istio.io/dataplane-mode=none' to explicitly opt out.

**Reference:** https://istio.io/latest/docs/ambient/usage/add-workloads/

### N-01 · Labels · Namespace/inventory

Namespace 'inventory' has no 'istio.io/dataplane-mode' label. Workloads here will not be enrolled in the ambient mesh after migration. Apply 'kubectl label namespace inventory istio.io/dataplane-mode=ambient' to enroll, or 'kubectl label namespace inventory istio.io/dataplane-mode=none' to explicitly opt out.

**Reference:** https://istio.io/latest/docs/ambient/usage/add-workloads/

## 🔵 Info

_(none)_
