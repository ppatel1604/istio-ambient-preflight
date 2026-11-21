# Istio Ambient Preflight Report

**Generated:** 2026-11-21T21:21:54Z  
**Context:** (current kubeconfig context)  
**Verdict:** Blocked

## Summary

| Severity | Count |
|---|---|
| 🔴 Blocker | 4 |
| 🟡 Warning | 2 |
| 🔵 Info | 2 |

## 🔴 Blockers

### N-02 · Labels · Namespace/legacy-injection

Namespace 'legacy-injection' is labeled for BOTH sidecar injection (istio-injection=enabled) and the ambient dataplane (istio.io/dataplane-mode=ambient). Istio's documented practice is one mode per namespace; mixed labels produce ambiguous behavior and typically indicate an incomplete migration. Remove the 'istio-injection' label ('kubectl label namespace legacy-injection istio-injection-') before enabling ambient on production workloads.

**Reference:** https://istio.io/latest/docs/ambient/usage/add-workloads/

### C-02 · Network · CiliumNetworkPolicy/pod-only-no-15008 in namespace payments

CiliumNetworkPolicy 'pod-only-no-15008' in ambient namespace 'payments' declares ingress rules but does not allow TCP port 15008. In ambient mode, mesh traffic arrives on the destination node via ztunnel using HBONE on TCP/15008; this policy will silently drop mesh traffic after migration. Add an ingress rule that permits TCP/15008 from the ztunnel DaemonSet (for example, select 'k8s:io.cilium.k8s.namespace.labels.kubernetes.io/metadata.name=istio-system' with toPorts port 15008), or migrate the L7 controls to an Istio AuthorizationPolicy.

**Reference:** https://istio.io/latest/docs/ambient/architecture/traffic-redirection/

### C-01 · Network · CiliumNetworkPolicy/pod-only-no-15008 in namespace payments

CiliumNetworkPolicy 'pod-only-no-15008' in ambient namespace 'payments' restricts ingress by pod-selector matchLabels (for example, allowing only sources like 'app=frontend'). In ambient mode with a waypoint proxy, mesh traffic arrives at the destination from the waypoint pod's identity rather than the original client; the original pod labels are no longer present on the connection, so this policy will silently drop waypoint-routed traffic after migration. Either add a fromEndpoints rule that admits the waypoint via its 'istio.io/gateway-name' label, or migrate L7 source-identity controls to an Istio AuthorizationPolicy (which evaluates against the original peer identity).

**Reference:** https://istio.io/latest/docs/ambient/usage/waypoint/

### G-01 · Ingress · Gateway/shop-legacy in namespace payments (Istio) + Gateway/shop-gw in namespace payments (Gateway API)

Istio Gateway 'payments/shop-legacy' and Gateway API Gateway 'payments/shop-gw' both claim overlapping hostnames: 'shop.example.com'. The two APIs are served by separate gateway deployments, so these hosts have two independent entry points and which one receives traffic depends on DNS and load-balancer wiring outside the mesh. Routes and policies attached to one gateway do not apply to the other. Move each hostname to a single API (Istio recommends the Gateway API for ambient) and remove it from the other gateway before migrating.

**Reference:** https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/

## 🟡 Warnings

### N-01 · Labels · Namespace/unlabeled-app

Namespace 'unlabeled-app' has no 'istio.io/dataplane-mode' label. Workloads here will not be enrolled in the ambient mesh after migration. Apply 'kubectl label namespace unlabeled-app istio.io/dataplane-mode=ambient' to enroll, or 'kubectl label namespace unlabeled-app istio.io/dataplane-mode=none' to explicitly opt out.

**Reference:** https://istio.io/latest/docs/ambient/usage/add-workloads/

### G-02 · Ingress · VirtualService/shop-routes in namespace payments

VirtualService 'shop-routes' in namespace 'payments' references gateway 'retired-gateway', which resolves to 'payments/retired-gateway' but no Istio Gateway with that name exists. Routes bound to that gateway are not programmed anywhere, so traffic you expect this VirtualService to handle at ingress is not reaching it today and will not after migration either. Either create the Gateway, correct the reference, or remove the stale binding.

**Reference:** https://istio.io/latest/docs/reference/config/networking/virtual-service/#VirtualService

## 🔵 Info

### P-02 · Pods · Pod/legacy-pod in namespace legacy-injection

Pod 'legacy-pod' in ambient namespace 'legacy-injection' carries stale sidecar-injection configuration (pod annotation 'sidecar.istio.io/inject=true' and namespace label 'istio-injection=enabled'). In ambient mode the injection directive is a no-op -- the pod runs but no sidecar is added. The stale directive misleads future operators into believing this workload is on the sidecar dataplane. Remove the label/annotation to reflect the pod's actual ambient enrollment.

**Reference:** https://istio.io/latest/docs/ambient/usage/add-workloads/

### P-01 · Pods · Pod/opt-out-pod in namespace payments

Pod 'opt-out-pod' in namespace 'payments' is labeled 'istio.io/dataplane-mode=none', explicitly opting out of the ambient mesh even though the namespace is enrolled as ambient. The pod will bypass ztunnel, L4 authorization, and mesh telemetry. This is fine if intentional (for example, a workload that manages its own TLS or networking); otherwise remove the pod label so the pod joins the namespace's ambient enrollment.

**Reference:** https://istio.io/latest/docs/ambient/usage/add-workloads/

