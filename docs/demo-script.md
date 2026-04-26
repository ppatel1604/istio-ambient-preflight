# Demo script

Recipe for the README's demo screencast. The goal is a 30-60 second clip
that shows the tool finding silent ambient-migration traps in a kind
cluster, ending on the rendered markdown report.

Re-record this whenever the finding format or fixture set changes.

## Setup (one-time)

```bash
# Fresh kind cluster (uses the fixture config -- two nodes, no kindnet).
kind create cluster --config tests/Integration/fixtures/kind-cluster.yaml

# Apply the enriched fixture set: namespaces, pods, CiliumNetworkPolicies.
# Installs the Cilium CNP CRD only; no Cilium runtime.
./tests/Integration/fixtures/setup-fixtures.sh
```

## Recording (use any terminal recorder, e.g. `asciinema rec` -> `agg`)

Suggested terminal: 100 cols x 30 rows, large readable font, dark
background.

```powershell
# 1. Show the help (proves it's a real PowerShell module).
Get-Help Invoke-AmbientPreflight -Examples

# 2. Run the preflight against the fixture cluster.
Import-Module ./src/IstioAmbientPreflight/IstioAmbientPreflight.psd1 -Force
Invoke-AmbientPreflight `
    -ExcludeNamespace local-path-storage,default `
    -OutputPath /tmp/preflight-demo.md

# 3. Show the rendered report (use `bat` if it's installed, otherwise `cat`).
bat /tmp/preflight-demo.md   # or: less /tmp/preflight-demo.md
```

The third step is the money shot: the markdown report shows three
Blockers, one Warning, and two Info findings -- every check the tool
ships with, fired in a single run.

## Postprocess

1. Trim head/tail dead time.
2. Convert to GIF: `agg recording.cast docs/demo.gif --speed 1.5 --cols 100 --rows 30`.
3. Keep the GIF under ~2 MB so GitHub renders it inline.

## Teardown

```bash
./tests/Integration/fixtures/teardown-fixtures.sh        # leave CRD installed
# or
kind delete cluster --name ambient-preflight-fixture     # nuke everything
```
