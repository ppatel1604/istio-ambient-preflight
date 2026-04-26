# Releasing istio-ambient-preflight

This file is the runbook for cutting a release. The publish step is
intentionally manual -- it requires a PowerShell Gallery API key that
should not live in CI.

## Prerequisites

One-time setup:

1. PowerShell Gallery account: https://www.powershellgallery.com/
2. API key for the account: profile -> "API Keys" -> "Create".
   The key is shown once; store it in your password manager.
3. PowerShell 7 + PowerShellGet 2.x or 3.x:
   ```powershell
   Install-Module -Name PowerShellGet -Force -Scope CurrentUser
   ```
4. PSScriptAnalyzer and Pester 5 installed locally:
   ```powershell
   Install-Module PSScriptAnalyzer -Scope CurrentUser
   Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser
   ```

## Release runbook

All paths in this section are repository-relative.

### 1. Bump the version

Edit `src/IstioAmbientPreflight/IstioAmbientPreflight.psd1`:

```powershell
ModuleVersion = '0.1.0'   # <- bump this
```

Use [SemVer](https://semver.org/): patch for fixes, minor for new
checks/features that are backward-compatible, major for breaking changes
to cmdlet parameters or finding shape.

### 2. Update CHANGELOG.md

Move everything under `## [Unreleased]` into a new section headed
`## [<version>] - <YYYY-MM-DD>`, then add a fresh empty `## [Unreleased]`
section above it. Keep the format from
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

### 3. Run the dry run

```powershell
./build/Publish-Module.ps1
```

This validates the manifest, runs PSScriptAnalyzer, runs the Pester unit
suite, and stages a publish-ready copy of the module under `.stage/`.
It does NOT upload anything. Fix anything it complains about before
proceeding.

### 4. Commit and push

```bash
git add src/IstioAmbientPreflight/IstioAmbientPreflight.psd1 CHANGELOG.md
git commit -m "release: v0.1.0"
git push
```

Wait for CI to go green on `main`. Don't release a branch with red CI.

### 5. Publish to PowerShell Gallery

```powershell
$env:PSGALLERY_API_KEY = '<your-psgallery-api-key>'
Publish-Module `
  -Path './.stage/IstioAmbientPreflight' `
  -NuGetApiKey $env:PSGALLERY_API_KEY `
  -Repository PSGallery
```

Verify the module shows up:
https://www.powershellgallery.com/packages/IstioAmbientPreflight

### 6. Tag the commit

```bash
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

### 7. Cut the GitHub release

```bash
gh release create v0.1.0 \
  --title "v0.1.0" \
  --notes-from-tag
```

Or paste the relevant `## [0.1.0]` section from `CHANGELOG.md` into the
release notes.

### 8. Sanity-test the published module

From a clean shell:

```powershell
Install-Module IstioAmbientPreflight -Scope CurrentUser
Get-Module IstioAmbientPreflight -ListAvailable | Format-List Name, Version
Invoke-AmbientPreflight -OutputPath /tmp/release-smoke.md
```

If anything's broken, **do not unlist** -- contact PowerShell Gallery
support to remove. (Republishing the same version is not allowed.)
Bump the version and re-release.

## What to do if Publish-Module fails

Common causes:

- **`The module name 'IstioAmbientPreflight' is already in use.`** --
  Someone else owns that name on PSGallery. Pick a new one and update
  the manifest and the README.
- **`A module with version X already exists.`** -- You can't republish
  the same version. Bump the patch number and try again.
- **API key invalid** -- Regenerate the key on the PSGallery site.

## Why the publish step is manual

Automating publish on every tag push is tempting but risky for a small
project: a typo in a tag pushes a broken release. The dry run script
captures the validation, leaving the maintainer in the loop for the
actual upload.
