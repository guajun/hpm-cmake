"""CI-only vendor fixtures, maintained independently of the installer."""
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import urllib.request
import venv
import zipfile

root = Path(os.environ['RUNNER_TEMP']) / 'hpm-test-tools'
root.mkdir(exist_ok=True)
sdk = root / 'sdk'
subprocess.run(['git', 'clone', '--depth', '1', '--branch', 'v1.12.1', 'https://github.com/hpmicro/hpm_sdk.git', str(sdk)], check=True)
windows = os.name == 'nt'
name = 'rv32imac_zicsr_zifencei_multilib_b_ext-' + ('win' if windows else 'linux')
archive = root / (name + ('.zip' if windows else '.tar.gz'))
urllib.request.urlretrieve('https://github.com/hpmicro/riscv-gnu-toolchain/releases/download/2023.10.18/' + archive.name, archive)
if windows:
    with zipfile.ZipFile(archive) as data:
        data.extractall(root)
else:
    with tarfile.open(archive) as data:
        data.extractall(root, filter='data')
venv.EnvBuilder(with_pip=True).create(root / 'python')
python = root / 'python' / ('Scripts/python.exe' if windows else 'bin/python')
subprocess.run([str(python), '-m', 'pip', 'install', 'PyYAML', 'Jinja2'], check=True)
with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream:
    for key, value in {'HPM_TEST_SDK': sdk, 'HPM_TEST_GCC': root / name, 'HPM_TEST_PYTHON': python}.items():
        stream.write(f'{key}={value}\n')
