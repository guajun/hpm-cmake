#!/usr/bin/env bash
set -euo pipefail
hpm_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
hpm_runner=${HPM_PYTHON:-python3}
hpm_args=("$@")
while (($#)); do
  if [[ $1 == --python-executable ]]; then hpm_runner=${2:?Missing Python executable}; break; fi
  shift
done
exec "$hpm_runner" "$hpm_root/scripts/hpm.py" "${hpm_args[@]}"
