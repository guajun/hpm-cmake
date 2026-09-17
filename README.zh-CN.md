# hpm-venv

[English](README.md) | [中文](README.zh-CN.md) · [一行安装](https://guajun.github.io/hpm-venv/)

**只负责在当前 shell 激活已有的 HPM SDK 工具。**

生成本地激活脚本，指向当前机器上已安装的 SDK、GNU GCC 和 Python。这里的 venv 指本地 shell 环境，不创建 Python 虚拟环境、不下载依赖、不管理版本。

## 安装，然后激活

在项目目录运行。空目录也可以，不需要 CMake 工程或已经生成的构建目录。

**PowerShell**

```powershell
& ([scriptblock]::Create((irm https://github.com/guajun/hpm-venv/releases/latest/download/install.ps1))) -Project . -Language zh
.\.hpm-venv\activate.ps1
```

**Bash**

```bash
bash <(curl -fsSL https://github.com/guajun/hpm-venv/releases/latest/download/install.sh) --project . --language zh
source .hpm-venv/activate.sh
```

激活后直接使用官方工程生成器和构建命令。hpm-venv 不生成 Presets、不导入 CMakeCache、不改 CMake 文件、不选择板卡或修改链接参数。工程配置、SDK/工具版本及兼容性由维护者负责。

激活设置 `HPM_SDK_BASE`、`GNURISCV_TOOLCHAIN_PATH`、`HPM_SDK_TOOLCHAIN_VARIANT=gcc`，并将所选 GCC/Python 命令放到当前 `PATH` 前部。小型本地 python/python3 启动脚本确保选中正确的解释器。仅影响当前 shell。

PowerShell 用 `.\.hpm-venv\activate.ps1 -Deactivate` 退出；Bash 用 `hpm_deactivate`。重复激活不会累积 PATH 项。

## 路径与非交互参数

路径选择顺序：显式参数、上次本机设置、当前环境变量、可选官方 sdk_env 目录、PATH 上可用命令。缺项交互询问；`-NonInteractive` / `--non-interactive` 直接报错，不等待输入。

| PowerShell | Bash | 内容 |
| --- | --- | --- |
| `-Project` | `--project` | 已存在的工作目录，默认 `.` |
| `-SdkEnvRoot` | `--sdk-env-root` | 可选官方 sdk_env 目录，包含 hpm_sdk、toolchains |
| `-SdkRoot` | `--sdk-root` | SDK 根目录，包含 cmake/hpm-sdk-config.cmake |
| `-ToolchainRoot` | `--toolchain-root` | GNU GCC 根目录，包含 bin/riscv32-unknown-elf-gcc[.exe] |
| `-PythonExecutable` | `--python-executable` | 已安装的 Python 可执行文件 |
| `-Version` | `--version` | 要下载的封装 release，默认 latest |
| `-NonInteractive` | `--non-interactive` | 不进行交互询问 |

[双语网页生成器](https://guajun.github.io/hpm-venv/#paths)可以填写路径，复制适用于 PowerShell/Bash 的完整一行命令。agent 建议显式填写 SDK、GCC、Python，避免发现路径时存在歧义。

生成器使用已有的 Python 3.9+；Windows 支持 PowerShell 5.1+，Linux 使用 Bash 与 curl。安装 hpm-venv 不需要 CMake、Ninja 或 Git。SDK 的 Python 依赖包按[厂商指南](https://hpm-sdk.readthedocs.io/en/latest/get_started.html)自行准备。

## 全部留在本机

只创建 `.hpm-venv/`：包含 `settings.json`、当前系统的激活脚本、Python 命令启动脚本和内部 `.gitignore`。无需提交任何生成文件；不读取或修改源码、CMake/Presets、仓库忽略规则。换机器时，用该机器的已有路径重新安装。

仓库原名 `hpm-cmake`，早期版本生成过本地 CMake 配置；hpm-venv 不使用这些文件。维护者可在确认不再需要时清理旧 `.hpm/`、`.hpm-cmake/`、生成的 UserPresets 或 lock，保留项目自己维护的配置。安装器不代做清理。

测试覆盖空目录安装、路径传参/环境变量、原工程文件保留、命令选择、重复激活与退出恢复，支持 Windows 和 Linux。无固件 example、构建封装、调试器或探针代码。

[HPM SDK](https://github.com/hpmicro/hpm_sdk) · [官方 sdk_env](https://github.com/hpmicro/sdk_env) · [厂商安装指南](https://hpm-sdk.readthedocs.io/en/latest/get_started.html)

MIT License。
