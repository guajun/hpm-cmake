# hpm-cmake

[English](README.md) | [中文](README.zh-CN.md) · [One-line installer](https://guajun.github.io/hpm-cmake/)

Project-local environments for **HPM firmware builds**, on Windows x64 and Linux x86_64. Official HPM tools own application/BSP initialization; native CMake owns the build.

## One command, on every machine

In the firmware source directory, run:

**Windows / PowerShell**

```powershell
& ([scriptblock]::Create((irm https://github.com/guajun/hpm-cmake/releases/latest/download/install.ps1))) -Project .
```

**Linux / Bash**

```bash
bash <(curl -fsSL https://github.com/guajun/hpm-cmake/releases/latest/download/install.sh) --project .
```

The command has two modes, selected automatically:

1. **First import:** no lock exists. Prepare the application with the official [SDK tools](https://github.com/hpmicro/sdk_env) / [native CMake workflow](https://hpm-sdk.readthedocs.io/en/latest/get_started.html), then import its generated `CMakeCache.txt`. The installer records its SDK revision, compiler profile, board and build configuration. Original source and `CMakeLists.txt` are preserved.
2. **After cloning the firmware repository:** `hpm-lock.json` exists. The same installer reads that lock and restores `.hpm/` for the current machine. No original SDK installation, build cache or generator is required. Existing lock and presets remain byte-for-byte unchanged. Repeating installation is supported.

Activate when you need the tools in your terminal:

```powershell
.\.hpm\activate.ps1
```

```bash
source .hpm/activate.sh
```

Then `cmake --preset default` and `cmake --build --preset default --parallel`. Activation affects only the current shell; PowerShell `-Deactivate` or Bash `hpm_deactivate` restores its previous environment. Presets also work without activation after installation.

## What goes in Git

| Commit | Do not commit |
| --- | --- |
| Firmware sources, BSP and `CMakeLists.txt` | `.hpm/`: SDK/GCC downloads, private Python, local paths, generated activation scripts/CMake hooks |
| `CMakePresets.json`: board/build configuration, portable across hosts | `build/`: CMake cache and firmware output |
| `hpm-lock.json`: exact dependency identities and platform artifact hashes | Original machine's vendor build directory and `CMakeUserPresets.json` |
| `.gitignore` | Machine environment variables |

**`.hpm/` is the equivalent of `.venv/`.** Delete/recreate it or clone elsewhere and run the same installer. Its generated `.hpm/environment.json` supplies current host paths to the tracked presets. Absolute machine paths never belong in the lock.

## The lock

`hpm-lock.json` schema 2 pins:

- Wrapper release version. `latest` installation honors an existing project's pinned wrapper; an explicit conflicting `-Version` / `--version` is rejected.
- SDK repository and exact commit.
- Official HPM GCC 13.2.0 packages for Windows and Linux, with download URLs, archive SHA-256 and compiler executable SHA-256.
- Exact Python package versions and platform wheel hashes (PyYAML 6.0.3, Jinja2 3.1.6, MarkupSafe 3.0.3).
- Windows private CPython 3.14.5 archive; Linux supported host Python range (3.10–3.14).

Linux uses the installed Python to create a private venv without pip; locked wheels are extracted into that environment. The host Python patch version is not pinned, so the lock is not a claim of bit-identical host runtimes. Windows bootstraps its own interpreter. The firmware remains a C/C++ project; no uv or Python project metadata is required.

Updates are deliberate lock changes, not an effect of reinstalling. Unsupported/custom legacy profiles fail instead of silently changing versions.

## Explicit paths / agents

Append parameters to the one-line command; the [bilingual web form](https://guajun.github.io/hpm-cmake/#paths) quotes them and always generates a non-interactive command.

| PowerShell | Bash | Meaning |
| --- | --- | --- |
| `-Project <path>` | `--project <path>` | Firmware source directory, default `.` |
| `-BuildDirectory <path>` | `--build-directory <path>` | **First import only.** Official CMakeCache folder, relative to Project; a unique matching folder is auto-detected |
| `-SdkRoot <path>` | `--sdk-root <path>` | Optional existing SDK; must match the lock |
| `-ToolchainRoot <path>` | `--toolchain-root <path>` | Optional existing GCC root; checked against the lock |
| `-SdkRevision <tag/commit>` | `--sdk-revision <tag/commit>` | Required when explicitly using a vendor SDK archive without Git metadata; declare its real revision |
| `-Version v0.3.0` | `--version v0.3.0` | Wrapper version; existing project lock takes precedence over `latest` |
| `-NonInteractive` | `--non-interactive` | Never prompt; missing/ambiguous first-import inputs fail immediately |

On first import, explicit paths take precedence over the original cache and `HPM_SDK_BASE` / `GNURISCV_TOOLCHAIN_PATH`. On restore, explicit paths override the ignored local binding; without one, dependencies are downloaded from the lock. Stale paths saved by a previous machine are never copied into Git. Existing modified SDKs or mismatched compilers are rejected.

Both hosts need Git, CMake 3.24+ and Ninja. Linux also needs Bash, curl, Python 3.10–3.14 with `venv` support. Only x86_64 Linux is supported by the current compiler profile. No global environment, shell profile or system package installation is performed.

## Upgrade from v0.2

The installer migrates supported schema-1 locks to schema 2 while retaining the SDK revision and Windows dependency versions. It backs up the old lock inside `.hpm/`. Original source stays unchanged. Old `.hpm-cmake/` and root `activate.ps1` are no longer used; remove those generated files from Git tracking, and use `.hpm/activate.ps1`. Review and commit the updated lock and Presets once. Future clones only need the same installer.

## Validation and scope

The repository contains no bundled firmware example or probe/debug scripts. Integration tests use the official SDK's `hello_world` only as a temporary fixture. They import, build, commit just firmware/config/lock, perform a real Git clone, restore without the original build directory, build again, and verify repeated installation and shell activation. Windows, Ubuntu 22.04 and Ubuntu 24.04 run in CI; no test operates hardware.

Official sources: [SDK setup and Linux instructions](https://hpm-sdk.readthedocs.io/en/latest/get_started.html), [HPM SDK](https://github.com/hpmicro/hpm_sdk), [official GCC releases](https://github.com/hpmicro/riscv-gnu-toolchain/releases/tag/2023.10.18), [Python](https://www.python.org/downloads/release/python-3145/). Structure and workflow inspired by [wch-cmake](https://guajun.github.io/wch-cmake/).

MIT license applies to this wrapper. Downloaded dependencies retain their upstream licenses and are not included in wrapper release assets.
