#!/usr/bin/env bash
set -euo pipefail
hpm_project=.
hpm_version=latest
hpm_args=()
while (($#)); do
  case "$1" in
    --project) hpm_project=${2:?Missing project}; shift 2;;
    --version) hpm_version=${2:?Missing version}; shift 2;;
    --build-directory|--sdk-root|--toolchain-root|--python-executable|--language) hpm_args+=("$1" "${2:?Missing value}"); shift 2;;
    --non-interactive) hpm_args+=("$1"); shift;;
    *) printf 'Unknown parameter: %s\n' "$1" >&2; exit 2;;
  esac
done
command -v python3 >/dev/null || { echo 'An existing Python 3.9+ is required.' >&2; exit 1; }
hpm_project=$(cd -- "$hpm_project" && pwd)
[[ -f "$hpm_project/CMakeLists.txt" ]] || { echo 'Project must contain CMakeLists.txt.' >&2; exit 1; }
if [[ $hpm_version == latest ]]; then
  hpm_version=$(curl -fsSL https://api.github.com/repos/guajun/hpm-cmake/releases/latest | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')
fi
[[ $hpm_version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release version.' >&2; exit 1; }
hpm_stage=$(mktemp -d "$hpm_project/.hpm-cmake-install-XXXXXXXX")
trap '[[ $hpm_stage == "$hpm_project"/.hpm-cmake-install-* ]] && rm -rf -- "$hpm_stage"' EXIT
hpm_base="https://github.com/guajun/hpm-cmake/releases/download/$hpm_version"
curl -fsSL "$hpm_base/hpm-cmake.zip" -o "$hpm_stage/hpm-cmake.zip"
curl -fsSL "$hpm_base/checksums.txt" -o "$hpm_stage/checksums.txt"
python3 - "$hpm_stage" <<'PY'
import hashlib,pathlib,re,sys,zipfile
p=pathlib.Path(sys.argv[1]); archive=p/'hpm-cmake.zip'
lines=re.findall(r'^([a-fA-F0-9]{64})\s+\*?hpm-cmake\.zip$',(p/'checksums.txt').read_text(),re.M)
if len(lines)!=1 or hashlib.sha256(archive.read_bytes()).hexdigest()!=lines[0].lower():
    raise SystemExit('Release checksum mismatch')
with zipfile.ZipFile(archive) as z:
    if any(not (p/name).resolve().is_relative_to(p.resolve()) for name in z.namelist()):
        raise SystemExit('Invalid archive path')
    z.extractall(p)
PY
python3 "$hpm_stage/hpm-cmake/scripts/hpm.py" --project "$hpm_project" "${hpm_args[@]}"
