# istio-ambient-preflight

> Preflight checks for migrating Kubernetes clusters to Istio Ambient Mode.

[![CI](https://github.com/ppatel1604/istio-ambient-preflight/actions/workflows/ci.yml/badge.svg)](https://github.com/ppatel1604/istio-ambient-preflight/actions)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/IstioAmbientPreflight.svg)](https://www.powershellgallery.com/packages/IstioAmbientPreflight)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

## The Problem

Istio Ambient Mode removes sidecars from the service mesh, promising simpler operations and lower resource overhead. But the migration from sidecar mode to ambient is *not* a drop-in change — and most of the ways it breaks are silent.

Three categories of problem bite almost every team attempting the migration:

**Network policy traps.** Cilium NetworkPolicies written for sidecar mode often don't account for the new ambient traffic paths — ztunnel for L4 and waypoint proxies for L7. Policies that looked correct quietly drop mesh traffic after migration.

**Label drift.** Ambient mode depends on the `istio.io/dataplane-mode` label at the namespace and pod level. Pods with `dataplane-mode=none` silently bypass the mesh even when the namespace is labeled `ambient`. Finding these after the fact is painful.

**Gateway conflicts.** Teams mid-way between classic Istio Gateway resources and the newer Gateway API end up with half-migrated ingress paths that work in sidecar mode and break in ambient.

This tool reads your cluster and tells you, in plain English, where each of these problems lives — *before* you flip the switch.

## What It Does

- Scans a live Kubernetes cluster (read-only, via your existing kubeconfig)
- Runs a battery of ambient-mode compatibility checks
- Produces a markdown report with:
  - A readiness verdict (Ready / Ready with Warnings / Blocked)
  - Each finding categorized as **Blocker**, **Warning**, or **Info**
  - A plain-English explanation of why ambient mode cares
  - A link to the relevant Istio, Cilium, or Gateway API documentation
  - The exact resources (namespace / pod / policy) affected

The tool never modifies your cluster. Period.

## Quick Start

```powershell
# Install from the PowerShell Gallery
Install-Module IstioAmbientPreflight -Scope CurrentUser

# Run against your current kubectl context
Invoke-AmbientPreflight

# Or target a specific context
Invoke-AmbientPreflight -Context my-cluster -OutputPath ./reports/prod.md

# Filter to a specific namespace
Invoke-AmbientPreflight -Namespace payments

# Scanning a local kind cluster? Suppress expected noise from its
# infrastructure namespace.
Invoke-AmbientPreflight -ExcludeNamespace local-path-storage

# Or suppress multiple operational namespaces on a managed cluster.
Invoke-AmbientPreflight -ExcludeNamespace argocd, monitoring, cert-manager
```

### Parameters

| Parameter | Purpose |
|---|---|
| `-Context` | kubectl context to target. Defaults to the current context. |
| `-OutputPath` | Markdown report path. Defaults to `./ambient-preflight-report.md`. |
| `-Namespace` | Scope checks to a single namespace. |
| `-ExcludeNamespace` | Extra namespaces to skip during namespace-label checks, on top of the built-in system list (`kube-system`, `kube-public`, `kube-node-lease`, `istio-system`, `cilium`). |

Prerequisites:

- PowerShell 7.0 or later (Windows, macOS, or Linux)
- `kubectl` on your PATH with a valid kubeconfig

## Example Output

See [`examples/demo-cluster/sample-report.md`](./examples/demo-cluster/sample-report.md) for a full example. A snippet:

```markdown
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

CiliumNetworkPolicy 'allow-frontend' in ambient namespace 'payments' declares
ingress rules but does not allow TCP port 15008. In ambient mode, mesh traffic
arrives on the destination node via ztunnel using HBONE on TCP/15008; this
policy will silently drop mesh traffic after migration. Add an ingress rule
that permits TCP/15008 from the ztunnel DaemonSet, or migrate the L7 controls
to an Istio AuthorizationPolicy.

**Reference:** https://istio.io/latest/docs/ambient/architecture/traffic-redirection/
```

## What It Checks

### Implemented

| ID | Check | Category | Severity |
|---|---|---|---|
| N-01 | Namespaces missing `istio.io/dataplane-mode=ambient` (and not explicitly opted out with `=none`) | Labels | Warning |
| N-02 | Namespaces with conflicting labels (both `istio-injection=enabled` and `istio.io/dataplane-mode=ambient`) | Labels | Blocker |
| C-02 | CiliumNetworkPolicies in ambient namespaces that do not allow TCP/15008 for ztunnel HBONE traffic | Network | Blocker |

### Planned for v0.1

| ID | Check | Category | Severity |
|---|---|---|---|
| P-01 | Pods explicitly opted out via `istio.io/dataplane-mode=none` in ambient namespaces | Labels | Info |
| P-02 | Pods with existing sidecar injection labels that will no-op in ambient | Labels | Info |
| C-01 | Cilium NetworkPolicies using pod-selector ingress that will fail with waypoint-routed traffic | Network | Blocker |
| G-01 | Mixed Istio Gateway + Gateway API resources on overlapping hosts | Ingress | Blocker |
| G-02 | VirtualServices referencing gateways that don't exist | Ingress | Warning |

See [ROADMAP.md](./ROADMAP.md) for the full plan.

## Who This Is For

Platform engineering and SRE teams running Istio on Kubernetes who are planning, executing, or debugging a sidecar-to-ambient migration. If you've been staring at ztunnel logs or wondering why your Cilium policies are silently dropping traffic, this tool is for you.

## Limitations

- Read-only. This tool advises; it does not migrate.
- Single-cluster. Multi-cluster scanning is on the roadmap.
- Istio-specific. No support for Linkerd, Cilium Service Mesh, or other meshes.
- Requires `kubectl` access with permission to list resources across target namespaces.

## Roadmap

See [ROADMAP.md](./ROADMAP.md) for the full plan. Highlights:

- **v0.2** — ArgoCD-compatible patch generation, JSON output for CI/CD
- **v0.3** — Waypoint proxy placement recommendations
- **v1.0** — Multi-cluster, HTML report, expanded check library

## Contributing

Contributions welcome — see [CONTRIBUTING.md](./CONTRIBUTING.md). New checks are especially welcome; each one is a self-contained private function with a Pester test.

## Consulting

This tool is free and always will be. If your team needs hands-on help with an ambient migration, service mesh architecture, or the broader platform-engineering stack (ArgoCD, Cilium, OAuth2-Proxy, Gateway API), I do consulting engagements — reach me on [LinkedIn](https://www.linkedin.com/in/YOUR_HANDLE).

## License

MIT — see [LICENSE](./LICENSE).
