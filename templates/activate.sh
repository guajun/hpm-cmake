#!/usr/bin/env bash
# Source this generated file; it affects only the current shell.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo 'Use: source .hpm/activate.sh' >&2; exit 1
fi
_hpm_env_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ ${1:-} != --deactivate ]] && [[ $(sha256sum "$_hpm_env_dir/../hpm-lock.json" | cut -d' ' -f1) != $(cat "$_hpm_env_dir/synced-lock.sha256") ]]; then
  echo 'Lock changed. Rerun the one-line installer.' >&2; unset _hpm_env_dir; return 1
fi
unset _hpm_env_dir
hpm_deactivate() {
  local name
  for name in PATH HPM_SDK_BASE GNURISCV_TOOLCHAIN_PATH HPM_SDK_TOOLCHAIN_VARIANT; do
    if [[ ${_hpm_saved_present[$name]} == 1 ]]; then export "$name=${_hpm_saved_values[$name]}"; else unset "$name"; fi
  done
  unset _hpm_saved_present _hpm_saved_values
  unset -f hpm_deactivate
}
if [[ ${1:-} == --deactivate ]]; then
  if declare -p _hpm_saved_values >/dev/null 2>&1; then hpm_deactivate; else unset -f hpm_deactivate; fi
  return
fi
if declare -p _hpm_saved_values >/dev/null 2>&1; then
  for _hpm_name in PATH HPM_SDK_BASE GNURISCV_TOOLCHAIN_PATH HPM_SDK_TOOLCHAIN_VARIANT; do
    if [[ ${_hpm_saved_present[$_hpm_name]} == 1 ]]; then export "$_hpm_name=${_hpm_saved_values[$_hpm_name]}"; else unset "$_hpm_name"; fi
  done
else
  declare -gA _hpm_saved_values=() _hpm_saved_present=()
  for _hpm_name in PATH HPM_SDK_BASE GNURISCV_TOOLCHAIN_PATH HPM_SDK_TOOLCHAIN_VARIANT; do
    _hpm_saved_values[$_hpm_name]=${!_hpm_name-}
    [[ -v $_hpm_name ]] && _hpm_saved_present[$_hpm_name]=1 || _hpm_saved_present[$_hpm_name]=0
  done
fi
export HPM_SDK_BASE=@SDK@
export GNURISCV_TOOLCHAIN_PATH=@GCC@
export HPM_SDK_TOOLCHAIN_VARIANT=gcc
export PATH=@PYTHON_BIN@:"$GNURISCV_TOOLCHAIN_PATH/bin:$PATH"
unset _hpm_name
printf 'Activated firmware environment: %s\n' @PROJECT@
