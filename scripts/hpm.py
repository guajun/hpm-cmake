"""Local activation and CMake configuration for an existing HPM application."""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
WINDOWS = os.name == 'nt'
sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')


def run(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True).strip()


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    text = value if isinstance(value, str) else json.dumps(value, indent=2, ensure_ascii=False) + '\n'
    with path.open('w', encoding='utf-8', newline='\n') as stream:
        stream.write(text)


def cache(path):
    result = {}
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        match = re.match(r'^([^/#][^:]*):([^=]+)=(.*)$', line)
        if match:
            result[match[1]] = (match[2], match[3])
    return result


def ask(args, name, message):
    if args.non_interactive:
        raise ValueError('Missing or ambiguous --' + name + '; non-interactive mode never prompts.')
    answer = input(message + ': ').strip().strip('"')
    if not answer:
        raise ValueError('Missing --' + name)
    return answer


def select_path(args, name, candidates, marker=None):
    explicit = getattr(args, name.replace('-', '_'))
    for candidate in ([explicit] if explicit else candidates):
        if candidate:
            path = Path(candidate).expanduser().resolve()
            if (path / marker).is_file() if marker else path.is_file():
                return path
    if explicit:
        raise ValueError('Invalid --' + name + ': ' + explicit)
    path = Path(ask(args, name, name)).expanduser().resolve()
    if not ((path / marker).is_file() if marker else path.is_file()):
        raise ValueError('Invalid --' + name)
    return path


def discover_build(args, project):
    candidates = []
    if args.build_directory:
        path = Path(args.build_directory)
        candidates = [(path if path.is_absolute() else project / path) / 'CMakeCache.txt']
    else:
        candidates = list(project.glob('*/CMakeCache.txt')) + list(project.glob('build/*/CMakeCache.txt')) + [project / 'CMakeCache.txt']
    matches = []
    for path in candidates:
        if not path.is_file():
            continue
        if path.is_relative_to(project) and '.hpm' in path.relative_to(project).parts:
            continue
        values = cache(path)
        if Path(values.get('CMAKE_HOME_DIRECTORY', ('', ''))[1]).resolve() == project and 'BOARD' in values and 'hpm-sdk_DIR' in values:
            matches.append((path, values))
    if len(matches) == 1:
        return matches[0]
    if args.build_directory:
        raise ValueError('--build-directory must contain the official build cache of this application.')
    for path, _ in matches:
        print(path.parent)
    args.build_directory = ask(args, 'build-directory', 'Official build folder / 官方构建目录')
    return discover_build(args, project)


def git_exclude(project):
    if not shutil.which('git'):
        return
    result = subprocess.run(['git', '-C', str(project), 'rev-parse', '--show-toplevel'], text=True, capture_output=True)
    if result.returncode:
        return
    root = Path(result.stdout.strip()).resolve()
    relative = project.relative_to(root).as_posix()
    if relative == '.':
        relative = ''
    else:
        relative += '/'
    if any(char in relative for char in '*?[]!#\n\r'):
        raise ValueError('Project path cannot be represented safely in Git local exclude rules.')
    user_file = relative + 'CMakeUserPresets.json'
    tracked = subprocess.run(['git', '-C', str(root), 'ls-files', '--error-unmatch', '--', user_file], capture_output=True)
    if tracked.returncode == 0:
        raise ValueError('CMakeUserPresets.json is tracked; untrack this local file before installing.')
    path = Path(run('git', '-C', project, 'rev-parse', '--path-format=absolute', '--git-path', 'info/exclude'))
    existing = path.read_text(encoding='utf-8') if path.exists() else ''
    additions = [value for value in ('/' + relative + '.hpm/', '/' + user_file) if value not in existing.splitlines()]
    if additions:
        write(path, existing + '\n# hpm-cmake: local machine configuration\n' + '\n'.join(additions) + '\n')


def install(args):
    project = Path(args.project).resolve()
    if not (project / 'CMakeLists.txt').is_file():
        raise ValueError('--project must contain the application CMakeLists.txt.')
    if not shutil.which('cmake') or not shutil.which('ninja'):
        raise ValueError('CMake and Ninja must already be available on PATH.')
    version = re.search(r'(\d+)\.(\d+)', run('cmake', '--version'))
    if tuple(map(int, version.groups())) < (3, 24):
        raise ValueError('CMake 3.24+ is required for local presets.')
    private = project / '.hpm'
    local_file = private / 'local.json'
    previous = read(local_file) if local_file.exists() else {}
    if args.build_directory or 'cacheVariables' not in previous:
        cache_path, values = discover_build(args, project)
        for key in ('CMAKE_PROJECT_INCLUDE', 'CMAKE_PROJECT_INCLUDE_BEFORE', 'CMAKE_PROJECT_TOP_LEVEL_INCLUDES', 'CMAKE_TOOLCHAIN_FILE'):
            if values.get(key, ('', ''))[1]:
                raise ValueError('Existing ' + key + ' requires explicit integration.')
        variables = {}
        for key, (kind, value) in values.items():
            if kind in ('INTERNAL', 'STATIC'):
                continue
            selected = re.match(r'^(BOARD|BOARD_SEARCH_PATH|HPM_BUILD_TYPE|CMAKE_BUILD_TYPE|HEAP_SIZE|STACK_SIZE|BUILD_FOR_SECONDARY_CORE|USE_LINKER_TEMPLATE)$', key) or re.match(r'^(CONFIG_|CUSTOM_|EXTRA_|HPM_SDK_LD_|CMAKE_(C|CXX|ASM|EXE_LINKER|STATIC_LINKER)_FLAGS)', key) or (kind == 'UNINITIALIZED' and not re.match(r'^(CMAKE_|python|Python|USE_CCACHE|GNURISCV_|HPM_SDK_|OPENOCD)', key))
            if selected:
                variables[key] = {'type': 'STRING' if kind == 'UNINITIALIZED' else kind, 'value': value}
        previous = {'sdk': str(Path(values['hpm-sdk_DIR'][1]).parent), 'toolchain': str(Path(values['CMAKE_C_COMPILER'][1]).parent.parent), 'python': values.get('python_exec', ('', ''))[1], 'cacheVariables': variables}
    variables = previous['cacheVariables']
    sdk = select_path(args, 'sdk-root', [previous.get('sdk'), os.environ.get('HPM_SDK_BASE')], 'cmake/hpm-sdk-config.cmake')
    gcc_name = 'riscv32-unknown-elf-gcc' + ('.exe' if WINDOWS else '')
    gcc = select_path(args, 'toolchain-root', [previous.get('toolchain'), os.environ.get('GNURISCV_TOOLCHAIN_PATH')], 'bin/' + gcc_name)
    python = select_path(args, 'python-executable', [previous.get('python'), sys.executable])
    try:
        run(python, '-c', 'import yaml, jinja2')
    except subprocess.CalledProcessError:
        raise ValueError('Selected SDK Python cannot import yaml/jinja2. Prepare it according to the vendor guide or pass --python-executable.')
    # Rebinding paths affects only this local configuration, not application code.
    for item in variables.values():
        if not isinstance(item, dict):
            continue
        text = item['value'].replace('\\', '/')
        for old, new in ((previous.get('sdk'), sdk.as_posix()), (previous.get('toolchain'), gcc.as_posix())):
            if old:
                text = re.sub(re.escape(old.replace('\\', '/').rstrip('/')) + r'(?=/|$|;)', lambda _: new, text, flags=re.I if WINDOWS else 0)
        item['value'] = text
    variables.update(USE_CCACHE='0', CMAKE_EXPORT_COMPILE_COMMANDS=True, python_exec={'type': 'FILEPATH', 'value': python.as_posix()}, CMAKE_PROJECT_INCLUDE='${sourceDir}/.hpm/cmake/hpm-project-hook.cmake')
    user_path = project / 'CMakeUserPresets.json'
    user = read(user_path) if user_path.exists() else {'version': 5}
    for path in (project / 'CMakePresets.json', user_path):
        if path.exists():
            for key in ('configurePresets', 'buildPresets'):
                if any(value.get('name') == 'hpm' for value in read(path).get(key, [])):
                    raise ValueError('An existing preset is named hpm. Rename it before integrating.')
    includes = user.setdefault('include', [])
    if '.hpm/presets.json' not in includes:
        includes.append('.hpm/presets.json')
    user['version'] = max(5, user['version'])
    git_exclude(project)
    private.mkdir(exist_ok=True)
    write(private / '.gitignore', '*\n')
    for name in ('hpm-project-hook.cmake', 'hpm-sdk-compat.cmake'):
        target = private / 'cmake' / name
        target.parent.mkdir(exist_ok=True)
        shutil.copyfile(ROOT / 'cmake' / name, target)
    write(private / 'presets.json', {'version': 5, 'configurePresets': [{'name': 'hpm', 'generator': 'Ninja', 'binaryDir': '${sourceDir}/.hpm/build', 'environment': {'HPM_SDK_BASE': sdk.as_posix(), 'GNURISCV_TOOLCHAIN_PATH': gcc.as_posix(), 'HPM_SDK_TOOLCHAIN_VARIANT': 'gcc'}, 'cacheVariables': variables}], 'buildPresets': [{'name': 'hpm', 'configurePreset': 'hpm', 'inheritConfigureEnvironment': True}]})
    write(local_file, {'sdk': str(sdk), 'toolchain': str(gcc), 'python': str(python), 'cacheVariables': variables})
    write(user_path, user)
    shutil.copyfile(ROOT / 'templates/activate.ps1', private / 'activate.ps1')
    template = (ROOT / 'templates/activate.sh').read_text(encoding='utf-8-sig')
    for key, value in {'SDK': str(sdk), 'GCC': str(gcc), 'PYTHON_BIN': str(python.parent), 'PROJECT': str(project)}.items():
        template = template.replace('@' + key + '@', shlex.quote(value))
    write(private / 'activate.sh', template)
    print('Local configuration ready. / 本地配置已生成。')
    print('  .\\.hpm\\activate.ps1' if WINDOWS else '  source .hpm/activate.sh')
    print('  cmake --preset hpm\n  cmake --build --preset hpm --parallel')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', default='.')
    for name in ('build-directory', 'sdk-root', 'toolchain-root', 'python-executable'):
        parser.add_argument('--' + name)
    parser.add_argument('--non-interactive', action='store_true')
    parser.add_argument('--language', choices=['en', 'zh'], default='en')
    install(parser.parse_args())


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print('hpm-cmake: ' + str(exc), file=sys.stderr)
        sys.exit(1)
