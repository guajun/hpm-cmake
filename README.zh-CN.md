# hpm-cmake

[English](README.md) | [简体中文](README.zh-CN.md) · [网页与命令生成器](https://guajun.github.io/hpm-cmake/)

先用 HPM 官方工具生成应用，再在源码目录执行**一行 release 安装命令**：

```powershell
& ([scriptblock]::Create((irm https://github.com/guajun/hpm-cmake/releases/latest/download/install.ps1))) -Project . -Language zh
```

安装器自动读取官方构建目录和 SDK/GCC 路径，只在信息缺失或存在歧义时交互询问。下载校验 release，保留原有应用 CMake、源码和 BSP，绑定现有工具路径并准备项目私有 Python。完成后直接运行：

```powershell
.\activate.ps1
cmake --preset default
cmake --build --preset default --parallel
```

每个新终端激活一次。环境变量只影响当前 PowerShell 进程；`./activate.ps1 -Deactivate` 恢复激活前的环境。CMake preset 也直接选择项目依赖；activate 让编译器、Python 及 SDK 命令可用于其他终端操作。

## 官方工程准备

下载 [官方 sdk_env](https://github.com/hpmicro/sdk_env/releases)，使用 `start_gui.exe` 或 `generate_project` 选择板卡、应用与构建模式。按照官方 [user_template 指南](https://github.com/hpmicro/sdk_env/blob/main/user_template/README_en.md) 或复制 sample，把应用源码放到 SDK 外部。官方生成的构建目录需要包含 `CMakeCache.txt`。

例如在官方 SDK 终端运行 `generate_project -b hpm6e00evk -t flash_xip` 会生成 `hpm6e00evk_build`。这里的板卡仅为示例；初始化、板卡选择和 BSP 继续由官方工具负责。

前置要求：Windows x64、64 位 PowerShell 5.1+、Git、CMake 3.24+、Ninja、官方 HPM GCC 13.2.0。SDK/GCC 通过项目内目录链接复用，保留所选安装目录即可。不安装全局命令、不写用户/系统环境变量、不安装全局 Python 包。

## 网页填写与非交互安装

在 [命令生成器](https://guajun.github.io/hpm-cmake/#paths) 填写路径并复制。生成的命令始终带 `-NonInteractive`，通过参数传入填写的值，按 PowerShell 规则处理空格与单引号。可供 agent 一次执行：

```powershell
& ([scriptblock]::Create((irm https://github.com/guajun/hpm-cmake/releases/latest/download/install.ps1))) -Project 'C:\firmware\my-app' -BuildDirectory 'hpm6e00evk_build' -SdkRoot 'C:\HPMicro\sdk_env\hpm_sdk' -ToolchainRoot 'C:\HPMicro\sdk_env\toolchains\rv32imac_zicsr_zifencei_multilib_b_ext-win' -SdkRevision 'v1.12.1' -Version 'v0.2.0' -Language zh -NonInteractive
```

请替换示例路径与版本。SDK 是 Git checkout 时不传 `-SdkRevision`；SDK ZIP 没有 Git 信息时必须提供实际官方 tag 或完整 commit。仅凭版本声明不能验证压缩包目录与该 commit 完全一致。`-NonInteractive` 是安装器参数，缺项或歧义时直接报错，不等待输入。

| 参数 | 默认值 / 行为 |
| --- | --- |
| `-Project <路径>` | 默认当前目录 `.`，须包含原始应用 CMakeLists.txt。 |
| `-BuildDirectory <路径>` | 自动识别项目内唯一的官方构建目录；相对 Project 解析，多项时需要选择。 |
| `-SdkEnvRoot <路径>` | 可选官方 sdk_env 目录，提供 SDK/GCC 默认路径和 generate_project 命令路径。 |
| `-SdkRoot <路径>` | SDK 根目录，含 cmake/hpm-sdk-config.cmake；显式参数优先于构建缓存、HPM_SDK_BASE。 |
| `-ToolchainRoot <路径>` | 含 bin/riscv32-unknown-elf-gcc.exe；缺省读取缓存、GNURISCV_TOOLCHAIN_PATH 或 PATH 上的编译器。 |
| `-SdkRevision <tag或commit>` | 仅无 Git 信息的 SDK ZIP 需要；Git checkout 自动固定其干净 commit。 |
| `-Version <版本>` | 默认 latest；填写 v0.2.0 固定封装版本。 |
| `-Language en\|zh` | 安装提示语言，默认 en。 |
| `-NonInteractive` | 无需值的开关。禁止询问，缺项直接报错并指出参数。 |

## 项目内的文件

随项目提交：原始应用、`activate.ps1`、`CMakePresets.json`、`hpm-lock.json`、`.hpm-cmake/`。

不提交：`.hpm/`（本机路径、SDK/GCC 目录链接、私有 Python、下载缓存）和 `build/hpm-default/`。绝对路径保存于 `.hpm/local.json`。SDK/GCC 校验后复用；Python 使用带校验值的官方 embeddable 3.14.5，以及 PyYAML 6.0.3、Jinja2 3.1.6、MarkupSafe 3.0.3。不需要 uv 或 Python 项目元数据。

换电脑后，可在空 `.hpm` 状态下运行 `./.hpm-cmake/sync.ps1` 下载锁定的 SDK/GCC 并准备 Python，再运行 activate。已有链接若指向被移走的工具，需明确移除链接或重新绑定，不递归删除其目标目录。已有缓存及 SDK checkout 时支持 `sync.ps1 -Offline`。

原工程的板卡、Flash/RAM 与构建类型继续由 `default` preset 保留。已有 Presets、封装文件、activate 脚本或冲突的 CMake hook 会被保留，安装器不会自动覆盖。含空格路径的链接参数问题由项目钩子处理，SDK 源码不变。官方 IDE 生成的未跟踪 Python 字节码缓存不算源码修改。

## 验证范围

[HPM6E00 blink](examples/hpm6e00-blink/) 是实测示例，不是初始化模板：J-Link EDU Mini / JTAG / Commander 9.46 已验证 RAM 运行、Flash 校验及断电重启闪烁。另有 HPM6750EVKMINI 构建测试，未做该板硬件验证。

开发验证覆盖官方生成器、两种板卡、release 安装、路径识别、非交互缺项失败、交互选择、参数引用、仅当前进程激活/恢复及原生构建。执行 `scripts/sync.ps1` 后运行 `powershell.exe -NoProfile -File tests/verify.ps1`；测试不连接探针。

官方资料：[安装指南](https://hpm-sdk.readthedocs.io/en/latest/get_started.html)、[原生 CMake](https://hpm-sdk.readthedocs.io/en/latest/cmake_quick_start.html)、[SDK 源码](https://github.com/hpmicro/hpm_sdk)、[GCC 发布包](https://github.com/hpmicro/riscv-gnu-toolchain/releases/tag/2023.10.18)、[Python 校验值](https://www.python.org/downloads/release/python-3145/)。流程参考 [wch-cmake](https://guajun.github.io/wch-cmake/)。

本仓库采用 MIT License。厂商 SDK、编译器、Python 和依赖包遵循各自许可证，不随封装 release 重新分发。
