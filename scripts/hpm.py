"""Generate local shell activation for existing HPM SDK tools."""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
WINDOWS = os.name == 'nt'
sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w', encoding='utf-8', newline='\n') as stream:
        stream.write(text)


def select(args, name, candidates, marker=None):
    explicit = getattr(args, name.replace('-', '_'))
    def valid(candidate):
        return candidate and ((Path(candidate) / marker).is_file() if marker else Path(candidate).is_file())
    for candidate in ([explicit] if explicit else candidates):
        if valid(candidate):
            # Preserve an existing Python venv's executable symlink: resolving
            # it to the base interpreter would discard that environment.
            return Path(os.path.abspath(os.path.expanduser(str(candidate))))
    if explicit:
        raise ValueError('Invalid --' + name + ': ' + explicit)
    if args.non_interactive:
        raise ValueError('Missing --' + name + '. Non-interactive mode never prompts.')
    labels = {'sdk-root': 'SDK 根目录', 'toolchain-root': 'GCC 根目录', 'python-executable': 'Python 可执行文件'}
    label = labels[name] if args.language == 'zh' else name
    answer = input(label + ': ').strip().strip('"')
    if not valid(answer):
        raise ValueError('Invalid --' + name)
    return Path(os.path.abspath(os.path.expanduser(answer)))


def install(args):
    project = Path(args.project).resolve()
    if not project.is_dir():
        raise ValueError('--project must be an existing directory; no application/build files are required.')
    private = project / '.hpm-venv'
    settings = private / 'settings.json'
    previous = json.loads(settings.read_text(encoding='utf-8-sig')) if settings.exists() else {}
    env_root = Path(args.sdk_env_root).resolve() if args.sdk_env_root else None
    sdk = select(args, 'sdk-root', [env_root / 'hpm_sdk' if env_root else None, previous.get('sdk'), os.environ.get('HPM_SDK_BASE')], 'cmake/hpm-sdk-config.cmake')
    gcc_name = 'riscv32-unknown-elf-gcc' + ('.exe' if WINDOWS else '')
    gcc_command = shutil.which(gcc_name)
    vendor_gcc = list((env_root / 'toolchains').glob('*/bin/' + gcc_name)) if env_root else []
    gcc = select(args, 'toolchain-root', [vendor_gcc[0].parent.parent if len(vendor_gcc) == 1 else None, previous.get('toolchain'), os.environ.get('GNURISCV_TOOLCHAIN_PATH'), Path(gcc_command).parent.parent if gcc_command else None], 'bin/' + gcc_name)
    vendor_python = env_root / 'tools/python3' / ('python.exe' if WINDOWS else 'bin/python3') if env_root else None
    python = select(args, 'python-executable', [vendor_python, previous.get('python'), os.environ.get('HPM_PYTHON'), sys.executable])
    # Only local paths are stored; no versions, dependency resolution or build configuration.
    write(settings, json.dumps({'sdk': str(sdk), 'toolchain': str(gcc), 'python': str(python)}, indent=2, ensure_ascii=False) + '\n')
    write(private / '.gitignore', '*\n')
    if WINDOWS:
        shutil.copyfile(ROOT / 'templates/activate.ps1', private / 'activate.ps1')
    else:
        template = (ROOT / 'templates/activate.sh').read_text(encoding='utf-8-sig')
        for key, value in {'SDK': str(sdk), 'GCC': str(gcc), 'PYTHON': str(python), 'PYTHON_BIN': str(python.parent), 'PROJECT': str(project)}.items():
            template = template.replace('@' + key + '@', shlex.quote(value))
        write(private / 'activate.sh', template)
    # SDK scripts can prefer python3 even on Windows where the selected interpreter
    # is named python.exe. Local launchers keep both names on the selected Python.
    for name in ('python', 'python3'):
        target = private / 'bin' / (name + ('.cmd' if WINDOWS else ''))
        text = '@echo off\n"' + str(python).replace('%', '%%') + '" %*\n' if WINDOWS else '#!/usr/bin/env bash\nexec ' + shlex.quote(str(python)) + ' "$@"\n'
        write(target, text)
        if not WINDOWS:
            target.chmod(0o755)
    print('本地激活脚本已生成：' if args.language == 'zh' else 'Local activation is ready:')
    print('  .\\.hpm-venv\\activate.ps1' if WINDOWS else '  source .hpm-venv/activate.sh')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', default='.')
    for name in ('sdk-root', 'toolchain-root', 'python-executable', 'sdk-env-root'):
        parser.add_argument('--' + name)
    parser.add_argument('--non-interactive', action='store_true')
    parser.add_argument('--language', choices=['en', 'zh'], default='en')
    install(parser.parse_args())


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as exc:
        print('hpm-venv: ' + str(exc), file=sys.stderr)
        sys.exit(1)
