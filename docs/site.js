'use strict';
let language=navigator.language.startsWith('zh')?'zh':'en';
try{language=localStorage.getItem('hpm-cmake-language')||language;}catch{}
const translations=Array.from(document.querySelectorAll('[data-zh]'),element=>({element,en:element.textContent,zh:element.dataset.zh}));
function render(){
 const shell=document.getElementById('shell').value;
 document.documentElement.lang=language==='zh'?'zh-CN':'en';
 for(const item of translations)item.element.textContent=item[language];
 document.getElementById('lang-en').setAttribute('aria-pressed',language==='en');
 document.getElementById('lang-zh').setAttribute('aria-pressed',language==='zh');
 document.getElementById('shell-label').textContent=shell==='bash'?'Bash':'PowerShell';
 document.getElementById('quick-command').textContent=HpmCommand.build({Project:'.'},language,shell).replace(/ -NonInteractive$| --non-interactive$/,'');
 document.getElementById('build-command').textContent=(shell==='bash'?'source .hpm/activate.sh':'.\\.hpm\\activate.ps1')+'\ncmake --preset hpm\ncmake --build --preset hpm --parallel';
 document.getElementById('readme-link').href=language==='zh'?'https://github.com/guajun/hpm-cmake/blob/main/README.zh-CN.md':'https://github.com/guajun/hpm-cmake#readme';
 const values=Object.fromEntries(HpmCommand.fields.map(key=>[key,document.getElementById(key).value]));
 try{document.getElementById('generated-command').textContent=HpmCommand.build(values,language,shell);document.getElementById('copy-generated').disabled=false;document.getElementById('command-error').textContent='';}
 catch{document.getElementById('generated-command').textContent='';document.getElementById('copy-generated').disabled=true;document.getElementById('command-error').textContent=language==='zh'?'请输入单行参数值。':'Use single-line values.';}
 document.getElementById('agent-command').textContent=HpmCommand.build({Project:shell==='bash'?'/work/firmware':'C:\\firmware',BuildDirectory:'hpm6e00evk_build',PythonExecutable:shell==='bash'?'/opt/sdk-python/bin/python':'C:\\sdk\\python\\python.exe'},language,shell);
}
for(const lang of ['en','zh'])document.getElementById('lang-'+lang).addEventListener('click',()=>{language=lang;try{localStorage.setItem('hpm-cmake-language',lang);}catch{}render();});
document.getElementById('shell').addEventListener('change',render);
document.getElementById('command-form').addEventListener('input',render);
document.getElementById('command-form').addEventListener('submit',event=>event.preventDefault());
for(const button of document.querySelectorAll('.copy'))button.addEventListener('click',async()=>{const value=document.getElementById(button.dataset.copy).textContent;let ok=false;try{await navigator.clipboard.writeText(value);ok=true;}catch{const area=document.createElement('textarea');area.value=value;document.body.append(area);area.select();ok=document.execCommand('copy');area.remove();}document.getElementById('copy-status').textContent=ok?(language==='zh'?'已复制。':'Copied.'):(language==='zh'?'请手动复制。':'Copy manually.');setTimeout(()=>{document.getElementById('copy-status').textContent='';},3000);});
render();
