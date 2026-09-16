'use strict';
const english = Object.fromEntries(Array.from(document.querySelectorAll('[data-i18n]'), node => [node.dataset.i18n, node.innerText]));
english.title = 'Your official project.\nOne command to get ready.';
const chinese = {
  navInstall:'安装',navPaths:'填写路径',navReference:'参数说明',title:'官方工程。\n一行命令，准备就绪。',lead:'用 HPM 官方工具生成应用。安装一次，激活当前终端，继续使用原生 CMake 开发。',requirements:'Windows x64 · PowerShell 5.1+ · Git · CMake 3.24+ · Ninja',installLabel:'安装到当前项目',copyInstall:'复制安装命令',quickHelp:'在应用源码目录运行。安装器自动识别已有构建配置和工具路径，仅在信息缺失时询问。',flowEyebrow:'三个步骤',flowTitle:'从官方工程，到日常构建。',step1Title:'用官方工具生成',step1Body:'在 start_gui 或 generate_project 中选择板卡、应用与构建类型。应用源码放在 SDK 目录之外。',vendorLink:'官方 SDK 环境包 ↗',step2Title:'执行一行安装命令',step2Body:'下载并校验 release，保留原始 CMake、应用源码与 BSP。将现有 SDK/GCC 路径绑定到本项目，自动准备私有 Python。',step3Title:'激活，然后构建',step3Body:'每个新终端激活一次。设置只对当前终端生效；运行 .\\activate.ps1 -Deactivate 可恢复激活前的环境。',builderEyebrow:'你的路径 · AGENT 也能直接执行',builderTitle:'填写路径，复制一行命令。',builderLead:'下方命令始终带 -NonInteractive，绝不等待输入。无法确定的路径会直接报错，并指出需要补充的参数。',projectLabel:'应用源码目录',projectHelp:'包含应用的 CMakeLists.txt。“.” 表示当前目录。',buildLabel:'官方构建目录',buildHelp:'包含 CMakeCache.txt。相对路径以 Project 为基准；留空时自动查找唯一匹配项。',advanced:'SDK 路径与版本（可自动识别时留空）',envLabel:'官方 sdk_env 目录',envHelp:'便捷指定 SDK、编译器和 generate_project 所在环境包。单独传入的 SDK/GCC 路径优先。',sdkLabel:'SDK 根目录',sdkHelp:'目录内包含 cmake/hpm-sdk-config.cmake。',gccLabel:'GCC 工具链根目录',gccHelp:'目录内包含 bin/riscv32-unknown-elf-gcc.exe，目前支持 HPM GCC 13.2.0。',revisionLabel:'SDK 压缩包版本',revisionHelp:'SDK ZIP 没有 Git 信息时必填，使用真实的官方 tag 或完整 commit；Git checkout 留空。',versionLabel:'hpm-cmake 发布版本',versionHelp:'留空使用 latest；填写 v0.2.0 可固定封装版本。',generatedLabel:'你的非交互命令',copyCommand:'复制命令',localOnly:'路径只保留在当前浏览器中。',agentTip:'供 agent 一次执行时，建议显式填齐 Project、BuildDirectory、SdkRoot、ToolchainRoot。SDK 压缩包还需 SdkRevision。参数按 PowerShell 规则引用，支持空格与单引号。',referenceEyebrow:'参数参考',referenceTitle:'终端用户和 agent 使用同一套参数。',resolution:'显式路径优先，其次检查官方构建缓存、环境变量和常见默认位置。交互模式只询问缺失或存在歧义的信息。',parameter:'参数',example:'格式 / 示例',meaning:'含义与默认行为',exampleTitle:'完整的非交互示例',copyExample:'复制示例',exampleHelp:'这里是示例路径，请替换为实际安装目录。命令在 PowerShell 终端执行；-NonInteractive 是安装器参数。',boundaryTitle:'从安装到激活，都属于当前项目。',boundaryBody:'安装生成的 activate.ps1 随项目提交；本机路径绑定保存在被忽略的 .hpm/local.json 中。SDK/GCC 通过本地目录链接复用，不写入用户级或系统级环境变量。',boundaryMore:'原工程的板卡和构建模式继续生效。换电脑后，可用项目内的 sync.ps1 准备锁定依赖。接入工具不生成 BSP，也不替你选择板卡。',readmeLink:'阅读完整指南 ↗',releaseLink:'发布文件 ↗',footer:'官方初始化 · 项目级激活 · 原生 CMake'
};
const parameterInfo = [
  ['Project',"'.' / 'C:\\firmware\\my-app'",'Application source folder. Default: current folder.','应用源码目录，默认当前目录。'],
  ['BuildDirectory',"'hpm6e00evk_build'",'Original CMakeCache folder; relative to Project. Auto-select only when exactly one build matches.','原始 CMakeCache 目录，相对 Project 解析。仅有一个匹配构建时自动选择。'],
  ['SdkEnvRoot',"'C:\\HPMicro\\sdk_env'",'Optional official environment root. Supplies SDK/GCC defaults and the generator command path.','可选的官方环境包目录，提供 SDK/GCC 默认路径及生成器命令路径。'],
  ['SdkRoot',"'C:\\HPMicro\\sdk_env\\hpm_sdk'",'Explicit SDK path; otherwise cache, HPM_SDK_BASE, or known defaults.','显式 SDK 路径；未填写时读取缓存、HPM_SDK_BASE 或默认位置。'],
  ['ToolchainRoot',"'C:\\tools\\hpm-gcc'",'Explicit compiler root; otherwise cache, GNURISCV_TOOLCHAIN_PATH, or compiler on PATH.','显式编译器根目录；未填写时读取缓存、GNURISCV_TOOLCHAIN_PATH 或 PATH 上的编译器。'],
  ['SdkRevision',"'v1.12.1' / '<40-char commit>'",'Required only for SDK archives without Git metadata. Must match the actual SDK.','仅无 Git 信息的 SDK 压缩包需要，必须匹配实际 SDK。'],
  ['Version',"'latest' / 'v0.2.0'",'Release to install. Default: latest.','安装的发布版本，默认 latest。'],
  ['Language',"'en' / 'zh'",'Language for setup prompts. Default: en. The page adds the selected language.','安装提示语言，默认 en；网页会传入当前选择的语言。'],
  ['NonInteractive','switch','Never prompt. Missing or ambiguous values fail immediately with the parameter name.','开关，无需值。禁止询问；缺项或歧义直接报错并指出参数。']
];
let language = 'en';
let statusTimer;
function renderCommand() {
  const values = Object.fromEntries(HpmCommand.fields.map(key => [key, document.getElementById(key).value]));
  const target = document.getElementById('generated-command');
  try {
    target.textContent = HpmCommand.build(values, language);
    document.getElementById('command-error').textContent = '';
    document.getElementById('copy-generated').disabled = false;
  } catch {
    target.textContent = '';
    document.getElementById('command-error').textContent = language === 'zh' ? '请使用单行路径或参数值。' : 'Use single-line paths and parameter values.';
    document.getElementById('copy-generated').disabled = true;
  }
}
function setLanguage(next) {
  language = next === 'zh' ? 'zh' : 'en';
  const text = language === 'zh' ? chinese : english;
  document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en';
  document.title = language === 'zh' ? 'hpm-cmake · 一行命令，项目环境就绪' : 'hpm-cmake · One command. Your project environment.';
  document.querySelectorAll('[data-i18n]').forEach(node => { node.textContent = text[node.dataset.i18n]; });
  document.getElementById('lang-en').setAttribute('aria-pressed', String(language === 'en'));
  document.getElementById('lang-zh').setAttribute('aria-pressed', String(language === 'zh'));
  document.getElementById('quick-command').textContent = `& ([scriptblock]::Create((irm ${HpmCommand.installer}))) -Project . -Language ${language}`;
  document.getElementById('readme-link').href = language === 'zh' ? 'https://github.com/guajun/hpm-cmake/blob/main/README.zh-CN.md' : 'https://github.com/guajun/hpm-cmake#readme';
  const body = document.getElementById('parameter-rows');
  body.replaceChildren(...parameterInfo.map(row => {
    const tr = document.createElement('tr');
    for (const value of ['-' + row[0], row[1], row[language === 'zh' ? 3 : 2]]) {
      const td = document.createElement('td'); td.textContent = value; tr.append(td);
    }
    return tr;
  }));
  document.getElementById('agent-command').textContent = HpmCommand.build({ Project:'C:\\firmware\\my-app',BuildDirectory:'hpm6e00evk_build',SdkRoot:'C:\\HPMicro\\sdk_env\\hpm_sdk',ToolchainRoot:'C:\\HPMicro\\sdk_env\\toolchains\\rv32imac_zicsr_zifencei_multilib_b_ext-win',SdkRevision:'v1.12.1',Version:'v0.2.0'},language);
  renderCommand();
  try { localStorage.setItem('hpm-cmake-language',language); } catch { /* Optional preference storage. */ }
}
document.querySelectorAll('.copy').forEach(button => button.addEventListener('click', async () => {
  const value = document.getElementById(button.dataset.copy).textContent;
  if (!value) return;
  let copied = false;
  try { await navigator.clipboard.writeText(value); copied = true; } catch {
    const area = document.createElement('textarea'); area.value=value; area.style.position='fixed'; area.style.opacity='0'; document.body.append(area); area.select();
    try { copied = document.execCommand('copy'); } catch { copied = false; }
    area.remove(); button.focus();
  }
  document.getElementById('copy-status').textContent = copied ? (language==='zh' ? '已复制，可直接粘贴到 PowerShell。' : 'Copied. Paste into PowerShell.') : (language==='zh' ? '复制失败，请手动选择命令文本。' : 'Copy failed. Select and copy the command manually.');
  clearTimeout(statusTimer); statusTimer=setTimeout(() => {document.getElementById('copy-status').textContent='';},3500);
}));
document.getElementById('command-form').addEventListener('input',renderCommand);
document.getElementById('command-form').addEventListener('submit',event => event.preventDefault());
document.getElementById('lang-en').addEventListener('click',() => setLanguage('en'));
document.getElementById('lang-zh').addEventListener('click',() => setLanguage('zh'));
let initial = navigator.language.startsWith('zh') ? 'zh' : 'en';
try { initial=localStorage.getItem('hpm-cmake-language') || initial; } catch { /* Browser preference fallback. */ }
setLanguage(initial);
