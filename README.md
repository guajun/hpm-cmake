# hpm-venv

[English](README.md) | [中文](README.zh-CN.md) · [One-line installer](https://guajun.github.io/hpm-venv/)

**Activate existing HPM SDK tools in the current shell.** That is the whole job.

`hpm-venv` generates local activation scripts pointing to the SDK, GNU GCC and Python already installed on your machine. The name describes a local shell environment; it does not create a Python virtual environment, download dependencies or manage versions.

## Install, then activate

Run in your project directory. An empty directory works too; no CMake project or generated build is required.

**PowerShell**

```powershell
& ([scriptblock]::Create((irm https://github.com/guajun/hpm-venv/releases/latest/download/install.ps1))) -Project .
.\.hpm-venv\activate.ps1
```

**Bash**

```bash
bash <(curl -fsSL https://github.com/guajun/hpm-venv/releases/latest/download/install.sh) --project .
source .hpm-venv/activate.sh
```

Use the official HPM generator and build commands afterward. hpm-venv does not generate Presets, import CMakeCache, edit CMake files, select boards, or change linker options. Application configuration, SDK/tool versions and compatibility are the maintainer's responsibility.

Activation sets `HPM_SDK_BASE`, `GNURISCV_TOOLCHAIN_PATH`, `HPM_SDK_TOOLCHAIN_VARIANT=gcc`, and prepends the selected GCC/Python commands to `PATH`. Small local `python`/`python3` launchers select the supplied interpreter consistently. Only the current shell is affected.

Exit with `.\.hpm-venv\activate.ps1 -Deactivate` on PowerShell or `hpm_deactivate` on Bash. Repeated activation does not accumulate PATH entries.

## Existing paths, explicit arguments

The installer uses explicit paths first, then previous local settings, current environment variables, the optional official sdk_env root, and available commands on PATH. Missing paths are requested interactively; `-NonInteractive` / `--non-interactive` fails without waiting.

| PowerShell | Bash | Value |
| --- | --- | --- |
| `-Project` | `--project` | Existing working directory, default `.` |
| `-SdkEnvRoot` | `--sdk-env-root` | Optional official sdk_env directory containing hpm_sdk and toolchains |
| `-SdkRoot` | `--sdk-root` | SDK root containing cmake/hpm-sdk-config.cmake |
| `-ToolchainRoot` | `--toolchain-root` | GNU GCC root containing bin/riscv32-unknown-elf-gcc[.exe] |
| `-PythonExecutable` | `--python-executable` | Existing Python executable |
| `-Version` | `--version` | Wrapper release to download, default latest |
| `-NonInteractive` | `--non-interactive` | Never prompt |

The [bilingual command builder](https://guajun.github.io/hpm-venv/#paths) produces a complete quoted one-line command for either shell. For agents, provide SDK/GCC/Python paths explicitly to avoid discovery ambiguity.

An existing Python 3.9+ runs this small generator. Windows supports PowerShell 5.1+; Linux uses Bash and curl. CMake, Ninja and Git are not installation prerequisites for hpm-venv. Prepare the SDK's Python packages separately according to the [vendor guide](https://hpm-sdk.readthedocs.io/en/latest/get_started.html).

## Local files only

Only `.hpm-venv/` is created: `settings.json`, the host's activation script, Python command launchers, and an internal `.gitignore`. Nothing needs to be committed. Source, CMake/Presets files and repository ignore rules are not read or modified. Each machine runs the installer with its own existing paths.

This repository was previously named `hpm-cmake`. Earlier releases generated local CMake configuration; hpm-venv does not use those files. Maintainers can remove known old generated `.hpm/`, `.hpm-cmake/`, UserPresets or lock files when no longer needed, preserving project-owned configuration. The installer does not perform that cleanup.

Tests cover installing in an empty directory, explicit/environment paths, existing project-file preservation, command selection, repeated activation and restoration on Windows and Linux. There is no firmware example, build-system wrapper, debugger or probe code.

[HPM SDK](https://github.com/hpmicro/hpm_sdk) · [Official sdk_env](https://github.com/hpmicro/sdk_env) · [Vendor setup guide](https://hpm-sdk.readthedocs.io/en/latest/get_started.html)

MIT License.
