# hpm-cmake

HPMicro SDK 的项目级环境封装，使用厂商原生 CMake。第一版面向 **Windows x64 / HPM6E00EVK**，包含可直接构建的 blink 和独立项目初始化脚本。

设计参考 [wch-cmake](https://github.com/guajun/wch-cmake) 与 uv 的项目隔离理念。构建所需的 SDK、GCC、Python 都属于当前项目；不修改用户/系统环境变量，不执行全局 pip 安装，不依赖 uv，也不需要将固件工程变成 Python 项目。

## 快速开始

前置工具：64 位 Windows、PowerShell 5.1+、Git、CMake 3.24+、Ninja。当前验证基线为 CMake 4.3.3、Ninja 1.13.2。使用已有的官方安装即可。

```powershell
git clone https://github.com/guajun/hpm-cmake.git
cd hpm-cmake
.\scripts\sync.ps1
.\scripts\doctor.ps1
cmake --preset debug
cmake --build --preset debug
```

固件输出为 `build/debug/output/demo.elf`、`demo.bin`。LED 亮、灭各 250 ms。

无需激活终端。`CMakePresets.json` 仅为构建进程设置 SDK、工具链路径；SDK 的 Python 解释器通过 `python_exec` 显式指定。构建 preset 继承对应 configure preset 的环境。原生 `find_package(hpm-sdk)` 负责芯片参数、启动代码、驱动和链接脚本。

固定版本 SDK 将两个带路径的链接参数放在 `target_link_libraries` 中，导致路径含空格时链接失败。`cmake/hpm-sdk-compat.cmake` 在应用侧把 map 文件和链接脚本参数移到 `target_link_options`，由 CMake 正确引用路径；不修改厂商 SDK，也不复制链接脚本。默认关闭 SDK 自动发现的系统 ccache。

## 独立工程

在本仓库中执行：

```powershell
.\hpm-cmake.ps1 init -Project C:\firmware\my-blink
```

目标必须为空。生成的工程包含构建脚本、源代码和依赖清单，可单独提交 Git，并按上述命令准备依赖和构建。它不依赖本仓库的安装位置。已有工程可参考本模板接入，第一版不自动覆盖或迁移已有工程。

## 依赖与隔离

| 组件 | 固定版本 | 本地目录 |
| --- | --- | --- |
| HPM SDK | `375f7cbcd19b0d43453b47ef7c4487a0b2689b37` | `.hpm/sdk` |
| HPM RISC-V GCC | 13.2.0 / 发布包 2023.10.18 | `.hpm/toolchain` |
| CPython embeddable x64 | 3.14.5 | `.hpm/python` |
| SDK Python 包 | PyYAML 6.0.3、Jinja2 3.1.6、MarkupSafe 3.0.3 | `.hpm/python/Lib/site-packages` |

`hpm-lock.json` 记录官方来源、SDK commit、压缩包和 wheel 的 SHA-256。`sync.ps1` 校验下载内容，暂存解压成功后才移入正式目录。SDK 是独立 Git checkout，保持厂商文件原样；它不作为本仓库的 submodule，也不提交到本仓库。

Python 只用于 SDK 构建辅助脚本，固件本身不需要 Python。使用 Python 官方 embeddable 发行包及固定的预编译 wheel，保留 `_pth` 隔离模式，只列出运行时自己的标准库及依赖目录；不加载系统 Python 包或 `PYTHONPATH`。三个固定 wheel 可直接解压，无 pip 安装钩子或额外构建步骤。

`.hpm/`、`build/` 和机器专用 `CMakeUserPresets.json` 被 Git 忽略。CMake、Ninja 是宿主工具，检查最低版本并记录验证版本，尚未由项目自动安装。SEGGER 软件及 USB 驱动也单独管理。

### 离线、手动下载与更新

完成一次准备后，可用 `.\scripts\sync.ps1 -Offline` 验证及使用已有 checkout 和下载缓存。也可以按照清单的 URL 手动下载压缩包/wheel，放到 `.hpm/downloads/<sha256前12位>-<原文件名>`，随后离线同步。SDK 可按官方仓库下载，放入 `.hpm/sdk`，需为清单指定 commit 的干净 Git checkout。

普通 configure/build 不联网、不更新依赖。升级时显式修改清单，并保存、移走相应旧目录，再执行 sync；首版遇到版本不一致或 SDK 本地修改会报错，不覆盖现有依赖。Python 环境记录完整清单 hash，清单变更后也需重新准备 `.hpm/python`。最后用 `cmake --preset debug --fresh` 重新配置。

## 构建预设

| Preset | 用途 | HPM_BUILD_TYPE |
| --- | --- | --- |
| `debug` | RAM 调试 | `ram` |
| `release` | RAM 优化构建 | `ram` |
| `flash-debug` | 外部 Flash XIP | `flash_xip` |

每个 preset 使用独立构建目录。修改应用代码在 `src/`，增加源文件用 SDK 原生 `sdk_app_src()`。修改开发板时编辑 preset 中的 `BOARD` 并核对板级接口，其他板卡尚未验证。

## J-Link / JTAG

从 [SEGGER 官网](https://www.segger.com/downloads/jlink/)安装 J-Link 软件及驱动。请先枚举探针，使用实际序列号：

```powershell
@('ShowEmuList', 'q') | & 'C:\Program Files\SEGGER\JLink\JLink.exe' -NoGui 1
```

RAM 运行（`123456789` 为示例，替换为实际序列号）：

```powershell
.\scripts\jlink.ps1 -Mode ram -Serial 123456789 -DryRun
.\scripts\jlink.ps1 -Mode ram -Serial 123456789
```

默认设备 `HPM6E80XVMX`、JTAG、4000 kHz；可通过参数修改设备、速度和 J-Link 路径。脚本从 ELF 读取入口地址，加载 RAM 后设置 PC 并运行。RAM 模式掉电后不会保留程序。

Flash XIP：

```powershell
cmake --preset flash-debug
cmake --build --preset flash-debug
.\scripts\jlink.ps1 -Mode flash -Serial 123456789 -DryRun
.\scripts\jlink.ps1 -Mode flash -Serial 123456789
```

Flash 命令会写入应用使用的 Flash 区域。`-DryRun` 仅生成并显示脚本；执行时通过 `-SelectEmuBySN` 选择探针，日志在 `.hpm/sessions/`。请关闭占用该探针的 Commander/GDB 会话。编译成功、下载运行成功和断电重启成功是分别验证的事项。

## 厂商资料与来源

- [HPM SDK 官方仓库](https://github.com/hpmicro/hpm_sdk) / [本项目固定 commit](https://github.com/hpmicro/hpm_sdk/tree/375f7cbcd19b0d43453b47ef7c4487a0b2689b37)
- [HPM SDK 安装指南](https://hpm-sdk.readthedocs.io/en/latest/get_started.html)
- [原生 CMake 快速开始](https://hpm-sdk.readthedocs.io/en/latest/cmake_quick_start.html)
- [RISC-V GNU 工具链发布页](https://github.com/hpmicro/riscv-gnu-toolchain/releases/tag/2023.10.18)
- [厂商 Windows SDK 环境包](https://github.com/hpmicro/sdk_env)
- [Python 3.14.5 官方下载与校验值](https://www.python.org/downloads/release/python-3145/)
- [Python embeddable 文档](https://docs.python.org/3/using/windows.html#the-embeddable-package)

本仓库脚本和模板采用 MIT License。下载的厂商 SDK、GCC、Python、Python 包和 SEGGER 软件分别遵循各自许可证，不适用本仓库许可证；不将这些下载内容重新发布到本仓库。

## 验证

本仓库可运行 `powershell.exe -NoProfile -File .\tests\verify.ps1`。该检查使用已准备的依赖，验证 RAM Debug、RAM Release、Flash Debug 构建，故意注入错误的 HPM/Python 环境变量，检查未同步依赖的报错和初始化的文件保护，并比较进程、用户及系统环境快照。它不会连接探针。GitHub Actions 在干净 Windows runner 上准备依赖并运行同一检查。

2026-09-16 本机验证：含空格的 OneDrive 路径构建通过；HPM6E00EVK 配合 J-Link EDU Mini / JTAG / Commander 9.46 的 RAM blink 已实测闪烁；Flash 下载及 J-Link 校验通过，开发板断电重启后自动继续闪烁。
