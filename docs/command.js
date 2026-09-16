(function (root) {
  'use strict';
  const installer = 'https://github.com/guajun/hpm-cmake/releases/latest/download/install.ps1';
  const fields = ['Project', 'BuildDirectory', 'SdkEnvRoot', 'SdkRoot', 'ToolchainRoot', 'SdkRevision', 'Version'];
  function quote(value) {
    const text = String(value).trim();
    if (/[\r\n\0]/.test(text)) throw new Error('Use a single-line value.');
    return "'" + text.replace(/'/g, "''") + "'";
  }
  function build(values, language) {
    let command = `& ([scriptblock]::Create((irm ${installer})))`;
    const options = { ...values, Project: values.Project?.trim() || '.' };
    for (const field of fields) {
      if (options[field]?.trim()) command += ` -${field} ${quote(options[field])}`;
    }
    return command + ` -Language ${quote(language === 'zh' ? 'zh' : 'en')} -NonInteractive`;
  }
  const api = { installer, fields, quote, build };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.HpmCommand = api;
})(typeof window !== 'undefined' ? window : globalThis);
