@echo off
rem kubectl test stub (Windows). Forwards all arguments to the sibling
rem kubectl-stub.ps1, which does the env-var-driven dispatch. Using a
rem PowerShell delegate keeps stdout binary-safe (cmd's `echo` and
rem `set /p` do not preserve JSON cleanly).
pwsh.exe -NoProfile -NoLogo -File "%~dp0kubectl-stub.ps1" %*
