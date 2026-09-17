#!/usr/bin/env bash
set -euo pipefail
hpm_project=.
hpm_version=latest
hpm_args=()
hpm_python=${HPM_PYTHON:-python3}
while (($#)); do
  case "$1" in
    --project) hpm_project=${2:?Missing project}; shift 2;;
    --version) hpm_version=${2:?Missing version}; shift 2;;
    --python-executable) hpm_python=${2:?Missing Python executable}; hpm_args+=("$1" "$2"); shift 2;;
    --sdk-env-root|--sdk-root|--toolchain-root|--language) hpm_args+=("$1" "${2:?Missing value}"); shift 2;;
    --non-interactive) hpm_args+=("$1"); shift;;
    *) printf 'Unknown parameter: %s\n' "$1" >&2; exit 2;;
  esac
done
command -v "$hpm_python" >/dev/null || { echo 'An existing Python 3.9+ is required.' >&2; exit 1; }
hpm_project=$(cd -- "$hpm_project" && pwd)
if [[ $hpm_version == latest ]]; then
  hpm_version=$(curl -fsSL https://api.github.com/repos/guajun/hpm-venv/releases/latest | "$hpm_python" -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')
fi
[[ $hpm_version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release version.' >&2; exit 1; }
hpm_stage=$(mktemp -d "$hpm_project/.hpm-venv-install-XXXXXXXX")
trap '[[ $hpm_stage == "$hpm_project"/.hpm-venv-install-* ]] && rm -rf -- "$hpm_stage"' EXIT
hpm_base="https://github.com/guajun/hpm-venv/releases/download/$hpm_version"
curl -fsSL "$hpm_base/hpm-venv.zip" -o "$hpm_stage/hpm-venv.zip"
curl -fsSL "$hpm_base/checksums.txt" -o "$hpm_stage/checksums.txt"
"$hpm_python" - "$hpm_stage" <<'PY'
import hashlib,pathlib,re,sys,zipfile
p=pathlib.Path(sys.argv[1]); archive=p/'hpm-venv.zip'
lines=re.findall(r'^([a-fA-F0-9]{64})\s+\*?hpm-venv\.zip$',(p/'checksums.txt').read_text(),re.M)
if len(lines)!=1 or hashlib.sha256(archive.read_bytes()).hexdigest()!=lines[0].lower():
    raise SystemExit('Release checksum mismatch')
with zipfile.ZipFile(archive) as z:
    if any(not (p/name).resolve().is_relative_to(p.resolve()) for name in z.namelist()):
        raise SystemExit('Invalid archive path')
    z.extractall(p)
PY
"$hpm_python" "$hpm_stage/hpm-venv/scripts/hpm.py" --project "$hpm_project" "${hpm_args[@]}"
