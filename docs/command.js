(function (root) {
  'use strict';
  const installer = 'https://github.com/guajun/hpm-venv/releases/latest/download/install.ps1';
  const fields = ['Project', 'SdkEnvRoot', 'SdkRoot', 'ToolchainRoot', 'PythonExecutable', 'Version'];
  const bashNames = {Project:'project',SdkEnvRoot:'sdk-env-root',SdkRoot:'sdk-root',ToolchainRoot:'toolchain-root',PythonExecutable:'python-executable',Version:'version'};
  function quote(value, shell='powershell') {
    const text = String(value).trim();
    if (/[\r\n\0]/.test(text)) throw new Error('Use a single-line value.');
    return "'" + text.replace(/'/g, shell==='bash' ? "'\"'\"'" : "''") + "'";
  }
  function build(values, language, shell='powershell') {
    let command = shell==='bash' ? 'bash <(curl -fsSL https://github.com/guajun/hpm-venv/releases/latest/download/install.sh)' : `& ([scriptblock]::Create((irm ${installer})))`;
    const options = { ...values, Project: values.Project?.trim() || '.' };
    for (const field of fields) {
      if (options[field]?.trim()) command += shell==='bash' ? ` --${bashNames[field]} ${quote(options[field],shell)}` : ` -${field} ${quote(options[field])}`;
    }
    return command + (shell==='bash' ? ` --language ${quote(language==='zh'?'zh':'en')} --non-interactive` : ` -Language ${quote(language === 'zh' ? 'zh' : 'en')} -NonInteractive`);
  }
  const api = { installer, fields, quote, build };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.HpmCommand = api;
})(typeof window !== 'undefined' ? window : globalThis);
