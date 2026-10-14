#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
task_root=$(pwd)
IFS= read -r task_version < .march-version
task_compiler="${MARCH_COMPILER:-${HOME}/.march/versions/${task_version}/bin/march}"
if [ ! -x "$task_compiler" ]; then
  echo "Install compiler with: forge toolchain install $task_version" >&2
  exit 1
fi
task_log=$(mktemp)
trap 'rm -f "$task_log"' EXIT HUP INT TERM
export MARCH_LIB_PATH="$task_root/lib:$task_root/../finance-core/lib:$task_root/../finance-ledger/lib"
"$task_compiler" --check fixtures/contracts/positive.march
check_rejected() {
  if "$task_compiler" --check "$1" > "$task_log" 2>&1; then
    echo "Expected rejection: $1" >&2
    exit 1
  fi
  if ! rg -q "$2" "$task_log"; then
    cat "$task_log" >&2
    exit 1
  fi
}
check_rejected fixtures/contracts/forged_network.march unknown_constructor
check_rejected fixtures/contracts/forged_asset.march unknown_constructor
check_rejected fixtures/contracts/forged_amount.march unknown_constructor
check_rejected fixtures/contracts/forged_reference.march unknown_constructor
check_rejected fixtures/contracts/forged_fee.march unknown_constructor
check_rejected fixtures/contracts/forged_context.march unknown_constructor
check_rejected fixtures/contracts/forged_event.march unknown_constructor
check_rejected fixtures/contracts/negative_precision.march refinement_violated
echo "8 compile-time contract checks passed (positive control accepted)"
