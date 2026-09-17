# hpm-cmake

[English](README.md) | [中文](README.zh-CN.md) · [一行安装与参数生成器](https://guajun.github.io/hpm-cmake/)

轻量的 HPM 固件项目**本地激活与 CMake 接入**。官方工具负责初始化应用和 BSP；SDK、编译器、Python 及依赖包的获取与版本，由项目维护者或其他工具负责。

本项目不解析依赖、不安装工具链、不生成 lock、不恢复版本，生成的文件也无需上传 Git。

## 本地安装

先按[官方流程](https://hpm-sdk.readthedocs.io/en/latest/get_started.html)准备工具和工程，并生成官方 CMake 构建目录。在固件源码目录运行：

**PowerShell**

```powershell
& ([scriptblock]::Create((irm https://github.com/guajun/hpm-cmake/releases/latest/download/install.ps1))) -Project . -Language zh
```

**Bash**

```bash
bash <(curl -fsSL https://github.com/guajun/hpm-cmake/releases/latest/download/install.sh) --project . --language zh
```

仅下载并校验轻量封装 release。SDK/GCC/Python 使用已有安装，路径从显式参数、官方 CMakeCache、本机配置或当前环境读取；缺项/歧义时交互询问。所选 Python 应已具备 SDK 所需依赖（包括 PyYAML、Jinja2），本工具不替用户安装这些包。

安装后：

```powershell
.\.hpm\activate.ps1
cmake --preset hpm
cmake --build --preset hpm --parallel
```

Bash 用 `source .hpm/activate.sh` 激活。只影响当前 shell；PowerShell 用 `-Deactivate`，Bash 用 `hpm_deactivate` 恢复环境。安装完成后，也可直接运行 CMake preset。

## 所有生成文件都留在本机

| 输出 | 用途 |
| --- | --- |
| `.hpm/local.json` | 当前机器的工具路径、导入的构建设置 |
| `.hpm/presets.json`、`.hpm/cmake/` | 本地 CMake 配置及路径兼容处理 |
| `.hpm/activate.ps1`、`.hpm/activate.sh` | 当前 shell 激活脚本 |
| `.hpm/build/` | 固件构建结果 |
| `CMakeUserPresets.json` | 接入本地 hpm preset，保留其他个人 preset |

**这些文件都不需要提交。** 原始源码、BSP、维护者的 `CMakePresets.json` 和 `.gitignore` 不改动。已有 Git 仓库通过 `.git/info/exclude` 写入本地忽略规则；`.hpm/` 自带忽略文件。如果安装后才执行 git init，请在暂存文件前再运行一次安装器，补齐本地忽略规则。

换机器后，先准备维护者选定的工具和官方构建配置，再运行同一条安装命令生成本机设置。同机器重复安装可复用已有本地配置；传入 BuildDirectory 则显式重新导入官方配置。此流程不承担可重复构建或环境版本恢复的保证。

## 参数与 agent 使用

[双语网页](https://guajun.github.io/hpm-cmake/#paths)可以填写参数并复制完整非交互命令。

| PowerShell | Bash | 含义 |
| --- | --- | --- |
| `-Project <路径>` | `--project <路径>` | 包含 CMakeLists.txt 的源码目录，默认当前目录 |
| `-BuildDirectory <路径>` | `--build-directory <路径>` | 官方 CMakeCache 所在目录，相对 Project 解析；唯一匹配项自动识别 |
| `-SdkRoot <路径>` | `--sdk-root <路径>` | 已安装 SDK 根目录，包含 cmake/hpm-sdk-config.cmake |
| `-ToolchainRoot <路径>` | `--toolchain-root <路径>` | 已安装 GNU GCC 根目录，包含 bin/riscv32-unknown-elf-gcc[.exe] |
| `-PythonExecutable <文件>` | `--python-executable <文件>` | 已准备好 SDK 依赖的 Python 可执行文件 |
| `-Version v0.4.0` | `--version v0.4.0` | 可选的封装 release 版本，默认 latest，不是依赖锁定 |
| `-NonInteractive` | `--non-interactive` | 不等待输入，缺项立即报错 |

例如，在 PowerShell 一行安装命令后追加 `-BuildDirectory 'hpm6e00evk_build' -SdkRoot 'C:\sdk\hpm_sdk' -ToolchainRoot 'C:\tools\hpm-gcc' -PythonExecutable 'C:\sdk\python\python.exe' -NonInteractive`。Bash 使用对应的双横线参数和 Linux 路径。不强制指定某一版 SDK/GCC，也不按预设版本清单校验它们。

前置条件：Windows/PowerShell 5.1+ 或 Linux/Bash、已有 Python 3.9+ 及 SDK 所需包、CMake 3.24+、Ninja。Git 可选，仅用于本地忽略规则。不改全局环境或 shell 启动文件。

## 旧版文件

v0.3 引入的版本管理职责已移除。之前生成的 `hpm-lock.json`、根目录 `CMakePresets.json` 和 `.hpm-cmake/` 不由 v0.4 使用。请维护者从固件仓库中移除确认属于旧封装的生成文件，保留项目自己维护的配置，然后重新接入官方构建目录。安装器不会自动删除或重新解释旧 lock。

测试独立准备官方 SDK/工具作为夹具，验证 Windows/Linux 构建、重复安装、跟踪文件不变、个人 Presets 保留及激活恢复。release 不附带测试 SDK、固件 example、烧录或调试代码。

[官方安装指南](https://hpm-sdk.readthedocs.io/en/latest/get_started.html) · [官方生成器](https://github.com/hpmicro/sdk_env) · [原生 CMake](https://hpm-sdk.readthedocs.io/en/latest/cmake_quick_start.html) · [GCC 下载](https://github.com/hpmicro/riscv-gnu-toolchain/releases)

MIT License。参考 [wch-cmake](https://guajun.github.io/wch-cmake/) 的轻量脚本工作流。
