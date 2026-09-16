# hpm-cmake

**官方工具生成工程，hpm-cmake 接入项目隔离环境，日常继续使用原生 CMake。**

参考 [wch-cmake](https://guajun.github.io/wch-cmake/) 的工作流程。本项目不生成 BSP、不提供芯片选择向导，也不把 HPM6E00 blink 作为所有项目的初始化模板。板卡、应用、链接脚本和构建类型由官方工具及应用自己的 CMake 决定。

文档入口：[guajun.github.io/hpm-cmake](https://guajun.github.io/hpm-cmake/)。当前宿主平台：Windows x64、PowerShell 5.1+、Git、CMake 3.24+、Ninja。

## 1. 用官方工具准备工程

从 [HPMicro sdk_env 发布页](https://github.com/hpmicro/sdk_env/releases) 下载官方环境，使用 `start_gui.exe` 选择 SDK、板卡、应用及构建类型，点击 **Generate**。自定义应用和 BSP 按官方的 [user_template 指南](https://github.com/hpmicro/sdk_env/blob/main/user_template/README_en.md) 组织。也可以使用官方 `generate_project` 命令：

```powershell
# 在官方 SDK 命令窗口中，切到包含应用 CMakeLists.txt 的目录
generate_project -b hpm6e00evk -t flash_xip
```

这里的板名只是示例，换成官方生成器选定的板。GUI 的输出目录可自选；上述 CLI 示例会生成 `hpm6e00evk_build/`。接入需要它生成的 `CMakeCache.txt`，不要求额外编译一次。此目录与应用源码目录是两个独立参数。

应用源码应位于 SDK 外部。使用 SDK 自带 sample 时，先按官方模板方式复制到自己的工作目录，再让官方工具针对该目录生成；import 会拒绝直接向 SDK 内的 samples 写入封装文件。

官方生成器由用户按厂商指南单独获取。本项目不重新打包 GUI，也不执行厂商的系统配置脚本。

## 2. 接入 hpm-cmake

### 从 clone 接入

```powershell
git clone https://github.com/guajun/hpm-cmake.git C:\tools\hpm-cmake
& C:\tools\hpm-cmake\hpm-cmake.ps1 import `
    -Project C:\firmware\my-app `
    -BuildDirectory C:\firmware\my-app\hpm6e00evk_build
```

### 从 release 接入

```powershell
& ([scriptblock]::Create((irm https://github.com/guajun/hpm-cmake/releases/latest/download/install.ps1))) `
    -Project C:\firmware\my-app `
    -BuildDirectory C:\firmware\my-app\hpm6e00evk_build
```

添加 `-Version v0.1.0` 可选择固定发布版本。也可手动从 [Releases](https://github.com/guajun/hpm-cmake/releases) 下载 `hpm-cmake.zip` 和 `checksums.txt`，校验、解压后运行同一个 `hpm-cmake.ps1 import` 命令。

安装器将版本归档暂存于目标工程中，校验 SHA-256 后接入并清理暂存目录。不安装全局命令。

**SDK 版本来源：** 如果原 SDK 是干净的 Git checkout，自动锁定其实际 commit。如果使用官方 SDK ZIP，两个入口都需要补充 `-SdkRevision v1.12.1`（替换为该 ZIP 的真实版本或完整 commit）；release tag 会在接入时解析为固定 commit。ZIP 模式不声称已验证原目录与该 commit 的内容完全相同，修改过的 BSP 应保存在自己的工程中。

## 3. 准备依赖并构建

进入应用源码目录：

```powershell
.\.hpm-cmake\sync.ps1
.\.hpm-cmake\doctor.ps1
cmake --preset default
cmake --build --preset default --parallel
```

无需激活终端。`default` 保留官方选择的板卡和构建类型，包括旧生成器的 `CMAKE_BUILD_TYPE=flash_xip` 写法，以及新工程的 `CMAKE_BUILD_TYPE=debug` + `HPM_BUILD_TYPE=flash_xip` 写法，不自行推断 RAM/Flash。可以在提交的 CMakePresets 中继续增加应用需要的组合。

原始生成目录继续保留，新构建输出到 `build/hpm-default/`。默认 SDK 应用输出为 `output/demo.elf`、`demo.bin`、`demo.map`；应用设置 `APP_NAME` 时仍由原生 SDK 决定名字。

## 接入边界

接入会添加：

```text
my-app/
├── CMakeLists.txt        # 原文件不改
├── src/                 # 原文件不改
├── boards/              # 如有自定义 BSP，仍归应用所有
├── CMakePresets.json     # 从官方构建配置生成，可提交
├── hpm-lock.json         # 固定依赖来源与校验值，可提交
├── .hpm-cmake/           # 环境脚本、CMake 钩子、导入记录，可提交
├── .hpm/                # SDK/GCC/Python/下载缓存，不提交
└── build/hpm-default/   # 不提交
```

`.gitignore` 只追加本项目的本地依赖/输出规则。已有 `CMakePresets.json`、`hpm-lock.json` 或 `.hpm-cmake` 时停止，避免覆盖现有配置；原工程已有 CMake project/toolchain 钩子时也要求显式整合。接入不是源码迁移器，应用的 `CMakeLists.txt` 和源文件保持逐字节不变。

导入读取 `BOARD`、`CMAKE_BUILD_TYPE`、`HPM_BUILD_TYPE`、板卡搜索路径、自定义链接脚本、`CONFIG_*`、`CUSTOM_*`、`EXTRA_*`、堆栈设置、常用编译/链接 flags 及其他命令行 cache 输入。SDK 内的路径重定位到项目私有 SDK；自定义 BSP/链接脚本路径转成相对于应用目录的路径。请把自定义文件与应用一起提交，兄弟目录布局需一起保留。导入结果可在 `.hpm-cmake/import.json` 和 Presets 中审阅。

`CMAKE_PROJECT_INCLUDE` 加载兼容钩子；链接参数处理延迟到配置结束，以适配 SDK 内部的 `project()` 调用。固定 SDK 的 map/链接脚本参数在含空格路径下引用不正确，封装在目标属性层修正，不改 SDK 文件、不替换链接脚本。默认关闭自动拾取系统 ccache。

## 依赖管理

- **SDK：** 使用原构建选定的官方 commit，下载到 `.hpm/sdk`。Git checkout 有代码修改时拒绝自动接入；官方 IDE 生成产生的未跟踪 Python 字节码缓存不算源代码修改。
- **GCC：** 当前依赖配置支持官方 HPM GCC 13.2.0 / 发布包 2023.10.18。接入检查原编译器版本和二进制 SHA-256，遇到其他工具链明确停止，不静默换编译器。
- **Python：** SDK 构建辅助工具使用官方 CPython embeddable 3.14.5，以及 PyYAML 6.0.3、Jinja2 3.1.6、MarkupSafe 3.0.3。隔离运行时放在 `.hpm/python`，不加载系统 Python 包。固件不是 Python 项目，不需要 uv、pip 全局安装或 `pyproject.toml`。
- **CMake / Ninja：** 复用宿主的官方安装。已在 CMake 4.3.3 和 4.4.3、Ninja 1.13.2 验证。

依赖清单包含下载地址和 SHA-256；sync 只写入应用的 `.hpm/`。普通 configure/build 不下载或更新依赖。已有下载缓存和 SDK checkout 后可执行 `.\.hpm-cmake\sync.ps1 -Offline`。

版本不匹配或 SDK 源码被修改时停止，首版不自动替换现有依赖目录。升级时保存、移走旧目录，更新锁定信息后重新 sync，并用 `cmake --preset default --fresh` 清除旧配置缓存。

## 示例与验证范围

`examples/hpm6e00-blink/` 仅是实测参考应用，按官方生成流程配置后再 import。它不参与 importer 的源码输出。该板使用 J-Link EDU Mini / JTAG / Commander 9.46，2026-09-16 已验证 RAM blink、Flash 烧录校验及断电重启后闪烁。示例中的 `run-jlink.ps1` 是该板的辅助脚本，不安装到任意导入工程。通用构建接入与物理探针操作分开。

开发验证：先在本工具仓库执行 `scripts/sync.ps1` 准备测试依赖，再运行 `powershell.exe -NoProfile -File tests/verify.ps1`。测试会获取固定 commit 的官方 `generate_project.cmd`，分别生成 HPM6E00EVK Flash 和 HPM6750EVKMINI RAM 工程，验证源码不变、clone/打包归档接入、含空格路径、环境隔离、锁定检查及原生构建。第二块板仅做构建验证，没有硬件实测。测试不连接探针。

## 官方资料

- [sdk_env / start_gui 官方说明](https://github.com/hpmicro/sdk_env)
- [官方自定义 Board/App 指南](https://kb.hpmicro.com/2024/10/08/%E5%A6%82%E4%BD%95%E5%BF%AB%E9%80%9F%E5%88%9B%E5%BB%BA%E7%94%A8%E6%88%B7%E8%87%AA%E5%AE%9A%E4%B9%89board%E5%92%8Capp%E5%B7%A5%E7%A8%8B/)
- [官方 SDK 安装指南](https://hpm-sdk.readthedocs.io/en/latest/get_started.html)
- [原生 CMake 指南](https://hpm-sdk.readthedocs.io/en/latest/cmake_quick_start.html)
- [HPM SDK 源码](https://github.com/hpmicro/hpm_sdk)
- [GCC 发布包](https://github.com/hpmicro/riscv-gnu-toolchain/releases/tag/2023.10.18)
- [Python 官方下载及校验值](https://www.python.org/downloads/release/python-3145/)

本仓库采用 MIT License。下载的 SDK、编译器、Python、Python 包、官方生成器及 SEGGER 软件分别遵循各自许可证，不作为本项目 release 的二进制内容发布。
