#!/bin/bash
# Runs a command with a stable environment. SwiftPM keys its manifest cache on
# the whole environment, and CI puts per-run values in it (run ids, CodeQL's
# job uuid), which recompiles every dependency manifest on every run.
set -euo pipefail

keep=$(env | cut -d= -f1 | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' \
  | grep -E '^(PATH|HOME|USER|TMPDIR|SHELL|LANG|DEVELOPER_DIR|SDKROOT|TOOLCHAINS|RUNNER_TEMP)$|^(CODEQL_|SEMMLE_|DYLD_|ODASA_|LGTM_)' \
  | grep -vE '^CODEQL_(ACTION_JOB_RUN_UUID|WORKFLOW_STARTED_AT)$')

args=()
for name in $keep; do args+=("$name=${!name}"); done
exec env -i "${args[@]}" "$@"
