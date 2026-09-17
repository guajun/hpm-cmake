"""Exercise initial import, Git clone restoration and repeatable installation."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
WIN = os.name == 'nt'


def run(*args, cwd=None, env=None):
    if WIN and str(args[0]).lower() == 'powershell.exe':
        env={k:v for k,v in (env or os.environ).items() if k.upper()!='PSMODULEPATH'}
    subprocess.run([str(a) for a in args], cwd=cwd, env=env, check=True)


def setup(project, *extra):
    if WIN:
        pairs={'--project':'-Project','--sdk-root':'-SdkRoot','--toolchain-root':'-ToolchainRoot','--build-directory':'-BuildDirectory','--non-interactive':'-NonInteractive'}
        run('powershell.exe','-NoProfile','-File',ROOT/'scripts/setup.ps1','-Project',project,'-NonInteractive',*[pairs.get(x,x) for x in extra])
    else:
        run('bash',ROOT/'hpm-cmake.sh','--project',project,'--non-interactive',*extra)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    work=ROOT/'.hpm/tests'
    work.mkdir(parents=True,exist_ok=True)
    test=Path(tempfile.mkdtemp(prefix='clone-',dir=work))
    seed=test/'seed'
    seed.mkdir()
    (seed/'CMakeLists.txt').write_text('cmake_minimum_required(VERSION 3.24)\nproject(seed NONE)\n')
    shutil.copyfile(ROOT/'hpm-lock.json',seed/'hpm-lock.json')
    (seed/'CMakePresets.json').write_text('{"version":5}')
    seed_extra=[]
    if os.environ.get('HPM_TEST_SDK'):
        seed_extra+=['--sdk-root',os.environ['HPM_TEST_SDK']]
    if os.environ.get('HPM_TEST_GCC'):
        seed_extra+=['--toolchain-root',os.environ['HPM_TEST_GCC']]
    setup(seed,*seed_extra)
    local=json.loads((seed/'.hpm/local.json').read_text())
    sdk=Path(local['sdk']); gcc=Path(local['toolchain']); python=Path(local['python'])
    app=test/'firmware with spaces'
    shutil.copytree(sdk/'samples/hello_world',app)
    original=digest(app/'CMakeLists.txt')
    env=os.environ.copy()
    env.update(HPM_SDK_BASE=str(sdk),GNURISCV_TOOLCHAIN_PATH=str(gcc),HPM_SDK_TOOLCHAIN_VARIANT='gcc')
    run('cmake','-S',app,'-B',app/'vendor-build','-G','Ninja','-DBOARD=hpm6e00evk','-DHPM_BUILD_TYPE=flash_xip','-DCMAKE_BUILD_TYPE=debug',f'-Dpython_exec={python}','-DUSE_CCACHE=0',env=env)
    setup(app,'--build-directory','vendor-build')
    assert digest(app/'CMakeLists.txt')==original
    lock_before=digest(app/'hpm-lock.json'); preset_before=digest(app/'CMakePresets.json')
    setup(app)
    assert digest(app/'hpm-lock.json')==lock_before and digest(app/'CMakePresets.json')==preset_before
    run('cmake','--preset','default',cwd=app)
    run('cmake','--build','--preset','default','--parallel',cwd=app)
    run('git','init','-q',app)
    run('git','-C',app,'config','core.autocrlf','false')
    run('git','-C',app,'add','.gitignore','CMakeLists.txt','CMakePresets.json','hpm-lock.json','src')
    run('git','-C',app,'-c','user.name=HPM Test','-c','user.email=test@example.invalid','commit','-qm','Firmware source and lock only')
    tracked=subprocess.check_output(['git','-C',str(app),'ls-files'],text=True)
    assert '.hpm/' not in tracked and 'activate' not in tracked
    clone=test/'clone on another machine'
    run('git','-c','core.autocrlf=false','clone','-q',app,clone)
    assert not (clone/'vendor-build').exists() and not (clone/'.hpm').exists()
    # A clone supplies only source, portable presets and lock. Tool locations are
    # local choices, never persisted into those versioned files.
    setup(clone,'--sdk-root',str(sdk),'--toolchain-root',str(gcc))
    assert digest(clone/'hpm-lock.json')==lock_before and digest(clone/'CMakePresets.json')==preset_before
    assert not subprocess.check_output(['git','-C',str(clone),'status','--porcelain'],text=True).strip()
    run('cmake','--preset','default',cwd=clone)
    run('cmake','--build','--preset','default','--parallel',cwd=clone)
    if WIN:
        script="$old=$env:PATH; $user=[Environment]::GetEnvironmentVariable('Path','User'); & ./.hpm/activate.ps1; $active=$env:PATH; & ./.hpm/activate.ps1; if($active -ne $env:PATH){throw 'Duplicate activation'}; & ./.hpm/activate.ps1 -Deactivate; if($old -ne $env:PATH -or $user -ne [Environment]::GetEnvironmentVariable('Path','User')){throw 'Environment changed'}"
        run('powershell.exe','-NoProfile','-Command',script,cwd=clone)
    else:
        run('bash','-c','before=$PATH; source .hpm/activate.sh; active=$PATH; source .hpm/activate.sh; [[ $PATH == "$active" ]]; hpm_deactivate; [[ $PATH == "$before" ]]',cwd=clone)
    (test/'result.json').write_text(json.dumps({'project':str(app),'clone':str(clone)}))
    print('PASS: native builds, source preservation, actual git clone, immutable lock/presets, repeat install, local activation.\n'+str(clone))


if __name__=='__main__':
    main()
