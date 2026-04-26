#!/usr/bin/env bash
# kubectl test stub (POSIX). Drives stdout/stderr/exit-code from
# environment variables so tests can pin per-case behavior, and logs the
# full argument vector to IAP_STUB_ARGS_FILE so tests can assert on what
# was passed. Mirrors tests/Unit/Helpers/kubectl-stub.ps1 for Windows.
if [ -n "$IAP_STUB_ARGS_FILE" ]; then
  printf '%s\n' "$*" >> "$IAP_STUB_ARGS_FILE"
fi
if [ -n "$IAP_STUB_STDERR" ]; then
  printf '%s' "$IAP_STUB_STDERR" >&2
fi
if [ -n "$IAP_STUB_STDOUT" ]; then
  printf '%s' "$IAP_STUB_STDOUT"
fi
exit "${IAP_STUB_EXIT:-0}"
