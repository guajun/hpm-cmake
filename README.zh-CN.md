# hpm-cmake

[English](README.md) | [中文](README.zh-CN.md) · [一行安装与参数生成器](https://guajun.github.io/hpm-cmake/)

聚焦 **HPM 固件开发**：官方工具初始化应用与 BSP，原生 CMake 构建；支持 Windows x64 与 Linux x86_64。

## 每次 clone 后，都运行同一条命令

在固件源码目录运行：

**Windows / PowerShell**

```powershell
& ([scriptblock]::Create((irm https://github.com/guajun/hpm-cmake/releases/latest/download/install.ps1))) -Project . -Language zh
```

**Linux / Bash**

```bash
bash <(curl -fsSL https://github.com/guajun/hpm-cmake/releases/latest/download/install.sh) --project . --language zh
```

安装器自动区分两个阶段：

1. **首次接入，没有 lock：** 用官方 SDK 工具或官方 CMake 流程生成工程，读取其 `CMakeCache.txt`，记录 SDK commit、工具链及板卡/构建配置；保留原始应用源码与 `CMakeLists.txt`。
2. **clone 固件仓库之后，已有 lock：** 同一条命令按 `hpm-lock.json` 重建当前机器的 `.hpm/`。不再需要原来的官方构建目录、生成器或安装路径；lock 与 Presets 不变。重复安装也不会因已有文件而失败。

在需要工具命令的新终端里激活：

```powershell
.\.hpm\activate.ps1
```

```bash
source .hpm/activate.sh
```

然后执行 `cmake --preset default` 和 `cmake --build --preset default --parallel`。激活仅影响当前 shell；PowerShell 的 `-Deactivate` 或 Bash 的 `hpm_deactivate` 恢复之前的环境。安装完成后也可直接使用 CMake preset，无需先激活。

## Git 边界

| 提交 Git | 不提交 Git |
| --- | --- |
| 固件源码、BSP、CMakeLists.txt | `.hpm/`：下载依赖、私有 Python、本机路径、生成的 activate 和 CMake hook |
| `CMakePresets.json`：可跨主机的板卡/构建配置 | `build/`：CMake 缓存与构建输出 |
| `hpm-lock.json`：版本与各平台校验值 | 原机器的官方构建目录、CMakeUserPresets.json |
| `.gitignore` | 机器环境变量 |

**`.hpm/` 就是这里与 `.venv/` 等价的目录。** clone 到别的目录或机器后重新安装；本机路径写入 `.hpm/environment.json`，由已提交的 Presets 引用。删除 `.hpm/` 后可重建，lock 不保存机器绝对路径。

## lock 锁定什么

原来已有的 `hpm-lock.json` 现在升级为 schema 2，明确锁定：

- 封装 release 版本。已有 lock 时，一行命令中的 latest 按项目固定版本恢复；显式指定冲突版本会报错。
- SDK 仓库与完整 commit。
- Windows/Linux 官方 HPM GCC 13.2.0 的下载地址、压缩包 SHA-256、编译器可执行文件 SHA-256。
- PyYAML 6.0.3、Jinja2 3.1.6、MarkupSafe 3.0.3 的固定版本及适配平台的 wheel 校验值。
- Windows 私有 CPython 3.14.5；Linux 宿主 Python 支持范围 3.10–3.14。

Linux 使用已安装的 Python 创建不带 pip 的项目 venv，再解压校验过的固定 wheel；宿主 Python 补丁版本不锁定，因此不声称主机运行环境逐字节相同。Windows 自动准备私有解释器。固件仍是 C/C++ 项目，无需 uv 或 Python 项目元数据。

重新安装不会顺便升级依赖。升级需要明确修改 lock 并验证；自定义旧依赖配置不会被静默替换。

## 参数与非交互运行

网页中英双语填写区可生成完整命令，始终带 `-NonInteractive` / `--non-interactive`，供 agent 一次执行。

| PowerShell | Bash | 含义 |
| --- | --- | --- |
| `-Project <路径>` | `--project <路径>` | 固件源码目录，默认 `.` |
| `-BuildDirectory <路径>` | `--build-directory <路径>` | 仅首次接入需要；包含官方 CMakeCache.txt，相对 Project 解析；唯一匹配项自动识别 |
| `-SdkRoot <路径>` | `--sdk-root <路径>` | 可选的现有 SDK，须匹配 lock |
| `-ToolchainRoot <路径>` | `--toolchain-root <路径>` | 可选的现有 GCC 根目录，校验版本与 hash |
| `-SdkRevision <tag或commit>` | `--sdk-revision <tag或commit>` | 使用没有 Git 信息的官方 SDK 压缩包时，声明真实版本 |
| `-Version v0.3.0` | `--version v0.3.0` | 封装版本；已有项目 lock 优先于 latest |
| `-NonInteractive` | `--non-interactive` | 禁止等待输入；首次接入缺项或歧义直接报错 |

首次接入的路径优先级是显式参数、官方缓存、HPM_SDK_BASE / GNURISCV_TOOLCHAIN_PATH。恢复时优先使用显式路径或本机绑定，没有时按 lock 下载。旧电脑的本地文件不提交，所以不会传到新 clone。修改过的 SDK 或不匹配的 GCC 会被拒绝。

两端需要 Git、CMake 3.24+、Ninja。Linux 还需要 Bash、curl、Python 3.10–3.14（含 venv）；当前工具链包仅支持 Linux x86_64。安装器不安装系统包、不修改 shell profile 或全局环境。

## 从 v0.2 迁移

支持的 schema-1 lock 会迁移为 schema 2，保留 SDK commit 和 Windows 依赖版本；旧 lock 备份在 `.hpm/`。原应用源码不变。旧 `.hpm-cmake/` 和根目录 `activate.ps1` 不再使用，请从 Git 取消跟踪这些生成文件，改用 `.hpm/activate.ps1`。第一次迁移审阅并提交更新后的 lock 与 Presets；后续 clone 只需重新安装。

## 范围与验证

仓库不再提供固件 example、J-Link 或调试脚本。测试临时使用官方 SDK 的 hello_world，验证首次接入、构建、只提交源码/配置/lock、真实 git clone、无原构建缓存恢复、再次编译、重复安装及激活恢复。Windows、Ubuntu 22.04/24.04 在 CI 构建；不操作硬件。

官方参考：[SDK 安装与 Linux 支持](https://hpm-sdk.readthedocs.io/en/latest/get_started.html)、[SDK 源码](https://github.com/hpmicro/hpm_sdk)、[GCC 发布](https://github.com/hpmicro/riscv-gnu-toolchain/releases/tag/2023.10.18)、[Python](https://www.python.org/downloads/release/python-3145/)。结构与流程参考 [wch-cmake](https://guajun.github.io/wch-cmake/)。

封装采用 MIT License；下载的 SDK、工具链及运行依赖保留各自许可证，不打包进封装 release。
