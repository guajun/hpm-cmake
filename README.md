# hpm-cmake

[English](README.md) | [简体中文](README.zh-CN.md) · [Website and command builder](https://guajun.github.io/hpm-cmake/)

Generate your application with the official HPMicro tools, then run **one release installer command** in its source folder:

```powershell
& ([scriptblock]::Create((irm https://github.com/guajun/hpm-cmake/releases/latest/download/install.ps1))) -Project .
```

The installer detects the official build directory and existing SDK/GCC paths. Missing information is requested interactively. It checks the release archive, preserves application CMake/source/BSP files, binds existing tools to this project, and prepares the SDK's private Python. When it finishes:

```powershell
.\activate.ps1
cmake --preset default
cmake --build --preset default --parallel
```

Activation changes only the current PowerShell process. Run it in each new terminal. `./activate.ps1 -Deactivate` restores the environment from before activation. CMake presets also supply the project paths directly; activation makes compiler, Python and SDK commands available for other terminal work.

## Prepare the official project

Download the [official sdk_env](https://github.com/hpmicro/sdk_env/releases). Use `start_gui.exe` or `generate_project` to select the board, application and build type. Keep application sources outside the SDK, using the official [user_template guide](https://github.com/hpmicro/sdk_env/blob/main/user_template/README_en.md) or a copied sample. The generated directory must contain `CMakeCache.txt`.

In the official SDK terminal, for example:

```powershell
generate_project -b hpm6e00evk -t flash_xip
```

This example creates `hpm6e00evk_build`. Other boards remain selected by the official tools. hpm-cmake does not initialize applications or generate BSPs.

Requirements: Windows x64, 64-bit PowerShell 5.1+, Git, CMake 3.24+, Ninja, and the official HPM GCC 13.2.0 package. SDK/GCC are reused through project-local directory junctions; keep the selected installations in place. No global command, user/system environment variable, or global Python package is installed.

## Non-interactive installation

Use the [web command builder](https://guajun.github.io/hpm-cmake/#paths) or pass all paths explicitly. Copied form commands always contain `-NonInteractive`, quote PowerShell arguments, and never wait for input.

```powershell
& ([scriptblock]::Create((irm https://github.com/guajun/hpm-cmake/releases/latest/download/install.ps1))) -Project 'C:\firmware\my-app' -BuildDirectory 'hpm6e00evk_build' -SdkRoot 'C:\HPMicro\sdk_env\hpm_sdk' -ToolchainRoot 'C:\HPMicro\sdk_env\toolchains\rv32imac_zicsr_zifencei_multilib_b_ext-win' -SdkRevision 'v1.12.1' -Version 'v0.2.0' -Language en -NonInteractive
```

Replace these example paths and versions with the actual installation. Omit `-SdkRevision` for a Git SDK checkout. For an archive, supply the real upstream tag/full commit: its original contents cannot be verified solely from a version label. `-NonInteractive` belongs to the installer, not the PowerShell executable. Failures identify the missing or ambiguous parameter.

| Parameter | Default / meaning |
| --- | --- |
| `-Project <path>` | Current folder (`.`); must contain the original application `CMakeLists.txt`. |
| `-BuildDirectory <path>` | Detect a unique original build in the project or its usual build folders. Relative to Project. Multiple matches require selection. |
| `-SdkEnvRoot <path>` | Optional official sdk_env root; supplies SDK/GCC defaults and the `generate_project` command path. |
| `-SdkRoot <path>` | SDK root containing `cmake/hpm-sdk-config.cmake`. Explicit path wins over build cache and `HPM_SDK_BASE`. |
| `-ToolchainRoot <path>` | Compiler root containing `bin/riscv32-unknown-elf-gcc.exe`. Otherwise cache, `GNURISCV_TOOLCHAIN_PATH`, or compiler on PATH. |
| `-SdkRevision <tag-or-commit>` | Required only for an SDK ZIP without Git metadata. Git checkouts use their exact clean commit. |
| `-Version <version>` | `latest`; use `v0.2.0` to pin this wrapper release. |
| `-Language en\|zh` | Setup prompt language; default `en`. |
| `-NonInteractive` | No prompts. Missing or ambiguous input fails with an actionable error. |

## What is installed

```text
my-app/
  CMakeLists.txt       # preserved, byte for byte
  src/                # preserved
  activate.ps1        # ready to run after installation; commit this
  CMakePresets.json    # imported official build selection; commit this
  hpm-lock.json        # fixed versions and artifact checksums; commit this
  .hpm-cmake/          # project scripts and CMake hooks; commit this
  .hpm/               # ignored local bindings, private Python, caches
    sdk/              # link to selected SDK on this machine
    toolchain/        # link to selected GCC on this machine
    local.json        # machine paths; never commit
  build/hpm-default/  # ignored firmware output
```

SDK and GCC are validated against the imported dependency profile. CPython embeddable 3.14.5 and the SDK packages PyYAML 6.0.3, Jinja2 3.1.6 and MarkupSafe 3.0.3 are downloaded with SHA-256 checks into the project. No uv or Python project metadata is needed. Official IDE generation can create untracked Python bytecode caches inside the SDK; source changes still fail validation.

On another machine, the committed scripts and lock remain portable. `./.hpm-cmake/sync.ps1` can download the locked SDK/compiler into an empty `.hpm` and prepare Python; then call `./activate.ps1`. Broken links to a removed installation need to be removed/rebound deliberately, never recursively delete their targets. Sync supports `-Offline` when the necessary checkout/cache is present.

The `default` preset preserves official board and build-mode choices, including legacy `CMAKE_BUILD_TYPE=flash_xip` and modern `HPM_BUILD_TYPE=flash_xip`. Additional presets remain normal application CMake configuration. The project hook fixes the vendor's map/linker-path quoting for paths containing spaces without editing SDK source. Existing presets, wrapper files, activation scripts or conflicting CMake hooks are preserved rather than overwritten.

## Scope and verification

[HPM6E00 blink](examples/hpm6e00-blink/) remains a hardware-tested example, not an initialization template. RAM execution, Flash verification and power-cycle blinking were tested with J-Link EDU Mini / JTAG / Commander 9.46. HPM6750EVKMINI is additionally build-tested, not hardware-tested. Probe operations remain separate from installation.

Development checks cover official project generation, two boards, release packaging/installation, path discovery, non-interactive failures, interactive selection, argument quoting, process-only activation/deactivation and native builds. Run `scripts/sync.ps1`, then `powershell.exe -NoProfile -File tests/verify.ps1`. No test connects to hardware.

Official references: [SDK setup](https://hpm-sdk.readthedocs.io/en/latest/get_started.html), [native CMake](https://hpm-sdk.readthedocs.io/en/latest/cmake_quick_start.html), [SDK source](https://github.com/hpmicro/hpm_sdk), [GCC package](https://github.com/hpmicro/riscv-gnu-toolchain/releases/tag/2023.10.18), [Python release](https://www.python.org/downloads/release/python-3145/). The workflow is inspired by [wch-cmake](https://guajun.github.io/wch-cmake/).

This repository is MIT licensed. Downloaded vendor SDK, compilers, runtimes and packages retain their own licenses and are not redistributed in the wrapper release.
