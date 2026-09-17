#!/usr/bin/env bash
set -euo pipefail
hpm_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec python3 "$hpm_root/scripts/hpm.py" "$@"
