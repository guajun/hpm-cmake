"""Verify local-only integration with maintainer-provided SDK and tools."""
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
        env = {k: v for k, v in (env or os.environ).items() if k.upper() != 'PSMODULEPATH'}
    subprocess.run([str(a) for a in args], cwd=cwd, env=env, check=True)


def setup(project, python):
    if WIN:
        run('powershell.exe', '-NoProfile', '-File', ROOT / 'scripts/setup.ps1', '-Project', project, '-PythonExecutable', python, '-NonInteractive')
    else:
        run('bash', ROOT / 'hpm-cmake.sh', '--project', project, '--python-executable', python, '--non-interactive')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    sdk = Path(os.environ['HPM_TEST_SDK'])
    gcc = Path(os.environ['HPM_TEST_GCC'])
    python = Path(os.environ['HPM_TEST_PYTHON'])
    work = ROOT / '.hpm/tests'
    work.mkdir(parents=True, exist_ok=True)
    test = Path(tempfile.mkdtemp(prefix='local-only-', dir=work))
    app = test / 'firmware with spaces'
    shutil.copytree(sdk / 'samples/hello_world', app)
    (app / '.gitignore').write_text('/vendor-build/\n') # maintained by the firmware project
    (app / 'CMakePresets.json').write_text('{"version":5,"configurePresets":[{"name":"maintainer","hidden":true}]}\n')
    run('git', 'init', '-q', app)
    run('git', '-C', app, 'config', 'core.autocrlf', 'false')
    run('git', '-C', app, 'add', '.')
    run('git', '-C', app, '-c', 'user.name=HPM Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'Maintainer-owned firmware files')
    originals = {name: digest(app / name) for name in ('CMakeLists.txt', 'CMakePresets.json', '.gitignore')}
    env = os.environ.copy()
    env.update(HPM_SDK_BASE=str(sdk), GNURISCV_TOOLCHAIN_PATH=str(gcc), HPM_SDK_TOOLCHAIN_VARIANT='gcc')
    def official(project):
        run('cmake', '-S', project, '-B', project / 'vendor-build', '-G', 'Ninja', '-DBOARD=hpm6e00evk', '-DHPM_BUILD_TYPE=flash_xip', '-DCMAKE_BUILD_TYPE=debug', f'-Dpython_exec={python}', '-DUSE_CCACHE=0', env=env)
    official(app)
    (app / 'CMakeUserPresets.json').write_text('{"version":5,"configurePresets":[{"name":"personal","hidden":true}],"vendor":{"test":{}}}')
    setup(app, python)
    setup(app, python)
    assert all(digest(app / name) == value for name, value in originals.items())
    assert read_user(app)['configurePresets'][0]['name'] == 'personal'
    assert not (app / 'hpm-lock.json').exists()
    assert not subprocess.check_output(['git', '-C', str(app), 'status', '--porcelain'], text=True).strip()
    run('cmake', '--preset', 'hpm', cwd=app)
    run('cmake', '--build', '--preset', 'hpm', '--parallel', cwd=app)
    clone = test / 'another machine'
    run('git', '-c', 'core.autocrlf=false', 'clone', '-q', app, clone)
    assert not (clone / '.hpm').exists() and not (clone / 'CMakeUserPresets.json').exists()
    # A new machine obtains its tools and official build configuration from the
    # project maintainer, not from a dependency resolver in this wrapper.
    official(clone)
    setup(clone, python)
    run('cmake', '--preset', 'hpm', cwd=clone)
    run('cmake', '--build', '--preset', 'hpm', '--parallel', cwd=clone)
    assert not subprocess.check_output(['git', '-C', str(clone), 'status', '--porcelain'], text=True).strip()
    if WIN:
        run('powershell.exe', '-NoProfile', '-Command', "$before=$env:PATH; & ./.hpm/activate.ps1; $active=$env:PATH; & ./.hpm/activate.ps1; if($active -ne $env:PATH){throw 'Duplicate activation'}; & ./.hpm/activate.ps1 -Deactivate; if($before -ne $env:PATH){throw 'Environment not restored'}", cwd=clone)
    else:
        run('bash', '-c', 'before=$PATH; source .hpm/activate.sh; active=$PATH; source .hpm/activate.sh; [[ $PATH == "$active" ]]; hpm_deactivate; [[ $PATH == "$before" ]]', cwd=clone)
    print('PASS: local-only output; no lock, downloads or tracked changes; personal presets preserved; Windows/Bash activation and firmware build.\n' + str(clone))


def read_user(project):
    return json.loads((project / 'CMakeUserPresets.json').read_text())


if __name__ == '__main__':
    main()
