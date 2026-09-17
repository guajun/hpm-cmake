"""Test shell activation and preservation of project files, without a build system."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
WIN=os.name=='nt'


def run(*args,cwd=None,env=None):
    if WIN and str(args[0]).lower()=='powershell.exe':
        env={k:v for k,v in (env or os.environ).items() if k.upper()!='PSMODULEPATH'}
    subprocess.run([str(arg) for arg in args],cwd=cwd,env=env,check=True)


def setup(project,sdk,gcc,extra=(),interpreter=None):
    interpreter=interpreter or sys.executable
    if WIN:
        run('powershell.exe','-NoProfile','-File',ROOT/'hpm-venv.ps1','-Project',project,'-SdkRoot',sdk,'-ToolchainRoot',gcc,'-PythonExecutable',interpreter,'-NonInteractive',*extra)
    else:
        run('bash',ROOT/'hpm-venv.sh','--project',project,'--sdk-root',sdk,'--toolchain-root',gcc,'--python-executable',interpreter,'--non-interactive',*extra)


def main():
    work=ROOT/'.hpm-venv/tests'
    work.mkdir(parents=True,exist_ok=True)
    test=Path(tempfile.mkdtemp(prefix='activation-',dir=work))
    # Only path markers are needed: this tool never compiles or executes the GCC.
    sdk=test/'vendor SDK'; (sdk/'cmake').mkdir(parents=True)
    (sdk/'cmake/hpm-sdk-config.cmake').write_text('# SDK marker\n')
    gcc=test/'vendor GCC'; (gcc/'bin').mkdir(parents=True)
    (gcc/'bin'/('riscv32-unknown-elf-gcc.exe' if WIN else 'riscv32-unknown-elf-gcc')).touch()
    project=test/'empty project with spaces';project.mkdir()
    setup(project,sdk,gcc)
    assert {p.name for p in project.iterdir()}=={'.hpm-venv'}
    sentinels={'CMakeLists.txt':'maintainer contents\n','CMakePresets.json':'arbitrary personal contents\n','CMakeUserPresets.json':'do not parse or modify\n','.gitignore':'maintainer rules\n'}
    for name,text in sentinels.items():(project/name).write_text(text)
    run('git','init','-q',project)
    run('git','-C',project,'config','core.autocrlf','false')
    run('git','-C',project,'add','.')
    run('git','-C',project,'-c','user.name=Environment Test','-c','user.email=test@example.invalid','commit','-qm','Maintainer files')
    setup(project,sdk,gcc)
    assert all((project/name).read_text()==text for name,text in sentinels.items())
    assert not subprocess.check_output(['git','-C',str(project),'status','--porcelain'],text=True).strip()
    if WIN:
        script=r'''$before=$env:PATH; $machine=[Environment]::GetEnvironmentVariable('Path','Machine'); $env:HPM_SDK_BASE='old-value'; & ./.hpm-venv/activate.ps1; $active=$env:PATH; & ./.hpm-venv/activate.ps1; if($active -ne $env:PATH){throw 'Duplicate PATH'}; $py=python3 -c 'import sys; print(sys.executable)'; if($LASTEXITCODE -ne 0 -or $py -ne (Get-Content ./.hpm-venv/settings.json -Raw|ConvertFrom-Json).python){throw 'Wrong Python'}; & ./.hpm-venv/activate.ps1 -Deactivate; if($env:PATH -ne $before -or $env:HPM_SDK_BASE -ne 'old-value' -or [Environment]::GetEnvironmentVariable('Path','Machine') -ne $machine){throw 'Environment not restored'}'''
        run('powershell.exe','-NoProfile','-Command',script,cwd=project)
    else:
        run('bash','-c','set -e; before=$PATH; export HPM_SDK_BASE=old-value; source .hpm-venv/activate.sh; active=$PATH; source .hpm-venv/activate.sh; [[ $PATH == "$active" ]]; python3 -c "import sys; print(sys.executable)"; hpm_deactivate; [[ $PATH == "$before" && $HPM_SDK_BASE == old-value ]]',cwd=project)
    settings=json.loads((project/'.hpm-venv/settings.json').read_text())
    assert set(settings)=={'sdk','toolchain','python'}
    detected=test/'environment discovery';detected.mkdir()
    environment=os.environ.copy()
    environment.update(HPM_SDK_BASE=str(sdk),GNURISCV_TOOLCHAIN_PATH=str(gcc),HPM_PYTHON=sys.executable)
    if WIN:
        run('powershell.exe','-NoProfile','-File',ROOT/'hpm-venv.ps1','-Project',detected,'-NonInteractive',env=environment)
    else:
        run('bash',ROOT/'hpm-venv.sh','--project',detected,'--non-interactive',env=environment)
    assert json.loads((detected/'.hpm-venv/settings.json').read_text())==settings
    if not WIN:
        import venv
        existing=test/'existing Python venv'
        venv.EnvBuilder(with_pip=False).create(existing)
        vproject=test/'uses existing venv';vproject.mkdir()
        setup(vproject,sdk,gcc,interpreter=existing/'bin/python3')
        result=subprocess.check_output(['bash','-c','source .hpm-venv/activate.sh; python3 -c "import sys; print(sys.prefix)"'],cwd=vproject,text=True)
        assert Path(result.strip().splitlines()[-1])==existing
    print('PASS: empty directory install, no CMake or Git edits, explicit Python selection, repeated activation and shell restoration.\n'+str(project))


if __name__=='__main__':main()
