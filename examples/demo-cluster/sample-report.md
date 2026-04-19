# Istio Ambient Preflight Report

**Generated:** 2026-04-19T04:53:20Z  
**Context:** (current kubeconfig context)  
**Verdict:** Ready with Warnings

## Summary

| Severity | Count |
|---|---|
| 🔴 Blocker | 0 |
| 🟡 Warning | 2 |
| 🔵 Info | 0 |

## 🔴 Blockers

_(none)_

## 🟡 Warnings

### N-01 · Labels · Namespace/default

Namespace 'default' has no 'istio.io/dataplane-mode' label. Workloads here will not be enrolled in the ambient mesh after migration. Apply 'kubectl label namespace default istio.io/dataplane-mode=ambient' to enroll, or 'kubectl label namespace default istio.io/dataplane-mode=none' to explicitly opt out.

**Reference:** https://istio.io/latest/docs/ambient/usage/add-workloads/

### N-01 · Labels · Namespace/local-path-storage

Namespace 'local-path-storage' has no 'istio.io/dataplane-mode' label. Workloads here will not be enrolled in the ambient mesh after migration. Apply 'kubectl label namespace local-path-storage istio.io/dataplane-mode=ambient' to enroll, or 'kubectl label namespace local-path-storage istio.io/dataplane-mode=none' to explicitly opt out.

**Reference:** https://istio.io/latest/docs/ambient/usage/add-workloads/

## 🔵 Info

_(none)_

