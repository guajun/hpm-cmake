"""Project-local HPM firmware environment. No host environment writes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
WINDOWS = os.name == 'nt'
HOST = ('windows' if WINDOWS else 'linux') + '-x86_64'
sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')


def run(*args, **kwargs):
    return subprocess.check_output([str(a) for a in args], text=True, **kwargs).strip()


def sha(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else hashlib.sha256(stream.read()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(value, indent=2, ensure_ascii=False) + '\n' if not isinstance(value, str) else value
    temporary = path.with_name(path.name + '.part')
    temporary.write_text(text, encoding='utf-8', newline='\n')
    temporary.replace(path)


def cache(path):
    result = {}
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        match = re.match(r'^([^/#][^:]*):([^=]+)=(.*)$', line)
        if match:
            result[match[1]] = (match[2], match[3])
    return result


def prompt(args, name, label):
    if args.non_interactive:
        raise ValueError(f'Missing/ambiguous --{name}. NonInteractive never prompts.')
    result = input(label + ': ').strip().strip('"')
    if not result:
        raise ValueError(f'Missing --{name}')
    return result


def artifact(item, private):
    name = item['sha256'][:12] + '-' + item['url'].rsplit('/', 1)[-1]
    path = private / 'downloads' / name
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        print('Downloading ' + name, flush=True)
        part = path.with_suffix(path.suffix + '.part')
        with urllib.request.urlopen(item['url'], timeout=90) as src, part.open('wb') as dest:
            shutil.copyfileobj(src, dest)
        if sha(part) != item['sha256']:
            raise ValueError('Download checksum mismatch: ' + name)
        part.replace(path)
    if sha(path) != item['sha256']:
        raise ValueError('Cached checksum mismatch: ' + name)
    return path


def extract(archive, target):
    target.mkdir(parents=True, exist_ok=True)
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as data:
            for member in data.namelist():
                if not (target / member).resolve().is_relative_to(target.resolve()):
                    raise ValueError('Archive entry escapes installation directory')
            data.extractall(target)
    else:
        with tarfile.open(archive) as data:
            # Vendor tar contains internal symlinks. Resolve both entry and link
            # destinations, then reject devices before extracting into staging.
            for member in data.getmembers():
                entry = (target / member.name).resolve()
                if not entry.is_relative_to(target.resolve()) or member.isdev():
                    raise ValueError('Unsafe archive member')
                if member.issym() or member.islnk():
                    link = (entry.parent / member.linkname).resolve() if member.issym() else (target / member.linkname).resolve()
                    if not link.is_relative_to(target.resolve()):
                        raise ValueError('Archive link escapes installation directory')
            data.extractall(target)


def validate_sdk(sdk, lock, revision_asserted=False):
    if not (sdk / 'cmake/hpm-sdk-config.cmake').is_file():
        raise ValueError(f'Invalid SDK: {sdk}')
    if (sdk / '.git').exists():
        if run('git', '-C', sdk, 'rev-parse', 'HEAD') != lock['sdk']['commit']:
            raise ValueError('SDK commit differs from lock; no automatic upgrade is allowed.')
        changes = run('git', '-C', sdk, 'status', '--porcelain', '--untracked-files=all').splitlines()
        if any(not re.match(r'^\?\? (?:.*/)?__pycache__/[^/]+\.pyc$', line) for line in changes):
            raise ValueError('SDK has local source changes; keep BSP changes in the application.')
    elif not revision_asserted:
        raise ValueError('An SDK archive requires its matching --sdk-revision.')


def compiler(root):
    return root / 'bin' / ('riscv32-unknown-elf-gcc.exe' if WINDOWS else 'riscv32-unknown-elf-gcc')


def validate_gcc(root, profile):
    executable = compiler(root)
    if not executable.is_file() or sha(executable) != profile['executableSha256']:
        raise ValueError('Compiler differs from the locked official HPM GCC binary.')
    if run(executable, '-dumpfullversion') != profile['version']:
        raise ValueError('Compiler version differs from lock.')


def revision(value, url):
    if re.fullmatch('[a-fA-F0-9]{40}', value):
        return value.lower()
    if not re.fullmatch('[A-Za-z0-9][A-Za-z0-9._-]*', value):
        raise ValueError('SDK revision must be a release tag or full commit.')
    lines = run('git', 'ls-remote', url, f'refs/tags/{value}', f'refs/tags/{value}^{{}}').splitlines()
    if not lines:
        raise ValueError('SDK release tag not found.')
    return next((line.split()[0] for line in lines if line.endswith('^{}')), lines[0].split()[0])


def first_import(args, project, profile):
    if (project / 'CMakePresets.json').exists():
        raise ValueError('Existing CMakePresets.json preserved. Integrate explicitly before first import.')
    if args.build_directory:
        build = Path(args.build_directory)
        build = build if build.is_absolute() else project / build
        candidates = [build / 'CMakeCache.txt']
    else:
        candidates = list(project.glob('*/CMakeCache.txt')) + list(project.glob('build/*/CMakeCache.txt')) + [project / 'CMakeCache.txt']
    matches = []
    for path in candidates:
        if not path.is_file():
            continue
        values = cache(path)
        if Path(values.get('CMAKE_HOME_DIRECTORY', ('', ''))[1]).resolve() == project and 'BOARD' in values and 'hpm-sdk_DIR' in values:
            matches.append((path, values))
    if len(matches) != 1:
        for path, _ in matches:
            print(path.parent)
        selected = prompt(args, 'build-directory', 'Official build folder / 官方构建目录')
        args.build_directory = selected
        return first_import(args, project, profile)
    cache_file, values = matches[0]
    for key in ('CMAKE_PROJECT_INCLUDE', 'CMAKE_PROJECT_INCLUDE_BEFORE', 'CMAKE_PROJECT_TOP_LEVEL_INCLUDES', 'CMAKE_TOOLCHAIN_FILE'):
        if values.get(key, ('', ''))[1]:
            raise ValueError(f'Existing {key} hook requires explicit integration.')
    original_sdk = Path(values['hpm-sdk_DIR'][1]).parent
    original_gcc = Path(values['CMAKE_C_COMPILER'][1]).parent.parent
    def choose(explicit, cached, env_name, marker, option):
        for path in (explicit, str(cached), os.environ.get(env_name)):
            if path and (Path(path) / marker).is_file():
                return Path(path).resolve()
            if explicit and path == explicit:
                raise ValueError(f'Invalid --{option}: {path}')
        return Path(prompt(args, option, option)).resolve()
    sdk = choose(args.sdk_root, original_sdk, 'HPM_SDK_BASE', 'cmake/hpm-sdk-config.cmake', 'sdk-root')
    gcc = choose(args.toolchain_root, original_gcc, 'GNURISCV_TOOLCHAIN_PATH', 'bin/' + compiler(Path()).name, 'toolchain-root')
    if project.is_relative_to(sdk):
        raise ValueError('Keep the application outside the vendor SDK.')
    lock = json.loads(json.dumps(profile))
    if (sdk / '.git').exists():
        commit = run('git', '-C', sdk, 'rev-parse', 'HEAD')
        if args.sdk_revision and revision(args.sdk_revision, lock['sdk']['url']) != commit:
            raise ValueError('Requested SDK revision differs from checkout.')
    else:
        value = args.sdk_revision or prompt(args, 'sdk-revision', 'Official SDK tag/commit / SDK 版本')
        commit = revision(value, lock['sdk']['url'])
        args.sdk_revision = value
    lock['sdk']['commit'] = commit
    lock['sdk'].pop('description', None)
    validate_sdk(sdk, lock, bool(args.sdk_revision))
    validate_gcc(gcc, lock['platforms'][HOST]['toolchain'])
    requirements = {line.split('#')[0].strip().lower() for line in (sdk / 'scripts/requirements.txt').read_text().splitlines()} - {''}
    if requirements != {'pyyaml', 'jinja2'}:
        raise ValueError('SDK Python requirements differ from the supported dependency profile.')
    variables = {}
    for key, (kind, value) in values.items():
        if kind in ('INTERNAL', 'STATIC'):
            continue
        selected = re.match(r'^(BOARD|BOARD_SEARCH_PATH|HPM_BUILD_TYPE|CMAKE_BUILD_TYPE|HEAP_SIZE|STACK_SIZE|BUILD_FOR_SECONDARY_CORE|USE_LINKER_TEMPLATE)$', key) or re.match(r'^(CONFIG_|CUSTOM_|EXTRA_|HPM_SDK_LD_|CMAKE_(C|CXX|ASM|EXE_LINKER|STATIC_LINKER)_FLAGS)', key) or (kind == 'UNINITIALIZED' and not re.match(r'^(CMAKE_|python|Python|USE_CCACHE|GNURISCV_|HPM_SDK_|OPENOCD)', key))
        if not selected:
            continue
        value = value.replace('\\', '/')
        for old, new in ((original_sdk, '$env{HPM_SDK_BASE}'), (original_gcc, '$env{GNURISCV_TOOLCHAIN_PATH}')):
            prefix = old.as_posix().rstrip('/')
            value = re.sub(re.escape(prefix) + r'(?=/|$|;)', lambda _: new, value, flags=re.I if WINDOWS else 0)
        if Path(value).is_absolute():
            value = '${sourceDir}/' + os.path.relpath(value, project).replace('\\', '/')
        variables[key] = {'type': 'STRING' if kind == 'UNINITIALIZED' else kind, 'value': value}
    variables.update(USE_CCACHE='0', CMAKE_EXPORT_COMPILE_COMMANDS=True)
    presets = {'version': 5, 'cmakeMinimumRequired': {'major': 3, 'minor': 24, 'patch': 0}, 'include': ['.hpm/environment.json'], 'configurePresets': [{'name': 'default', 'inherits': 'hpm-local', 'generator': 'Ninja', 'binaryDir': '${sourceDir}/build/hpm-default', 'cacheVariables': variables}], 'buildPresets': [{'name': 'default', 'configurePreset': 'default', 'inheritConfigureEnvironment': True}]}
    write(project / 'hpm-lock.json', lock)
    write(project / 'CMakePresets.json', presets)
    args.sdk_root, args.toolchain_root = str(sdk), str(gcc)
    return lock


def migrate(project, old, profile):
    # Version 0.2 locks only covered Windows. Expand the supported profile without
    # changing its SDK commit or existing artifact checksums.
    if old.get('schema') != 1:
        raise ValueError('Unsupported lock schema.')
    if old['toolchain']['sha256'] != profile['platforms']['windows-x86_64']['toolchain']['sha256'] or old['python']['version'] != profile['platforms']['windows-x86_64']['python']['version']:
        raise ValueError('Custom legacy dependencies require an explicit lock migration.')
    presets = read(project / 'CMakePresets.json')
    for preset in presets.get('configurePresets', []):
        variables = preset.get('cacheVariables', {})
        if variables.get('CMAKE_PROJECT_INCLUDE') != '${sourceDir}/.hpm-cmake/cmake/hpm-project-hook.cmake':
            raise ValueError('Custom legacy presets preserved; migrate hooks explicitly.')
        variables.pop('CMAKE_PROJECT_INCLUDE')
        variables.pop('python_exec', None)
        preset.pop('environment', None)
        preset['inherits'] = 'hpm-local'
    presets['include'] = ['.hpm/environment.json']
    result = json.loads(json.dumps(profile))
    result['sdk'] = old['sdk']
    result['platforms']['windows-x86_64']['toolchain'].update(old['toolchain'])
    result['platforms']['windows-x86_64']['python'] = old['python']
    backup = project / '.hpm/legacy-lock.json'
    write(backup, old)
    write(project / 'hpm-lock.json', result)
    write(project / 'CMakePresets.json', presets)
    print('Migrated legacy lock. Old .hpm-cmake/ and root activate.ps1 are no longer used; untrack these generated files in Git.')
    return result


def prepare_python(private, profile):
    target = private / 'python'
    if WINDOWS:
        # setup.ps1 bootstraps this pinned runtime before invoking this module.
        executable = target / 'python.exe'
        if run(executable, '-c', 'import platform; print(platform.python_version())') != profile['version']:
            raise ValueError('Private Python runtime differs from lock.')
        site = target / 'Lib/site-packages'
        packages = profile['packages']
    else:
        import venv
        version = sys.version_info[:2]
        if not (tuple(map(int, profile['minimum'].split('.'))) <= version < tuple(map(int, profile['maximumExclusive'].split('.')))):
            raise ValueError('Linux requires Python 3.10-3.14; the interpreter is a host prerequisite.')
        executable = target / 'bin/python3'
        if not executable.exists():
            venv.EnvBuilder(with_pip=False).create(target)
        site = Path(run(executable, '-I', '-c', 'import sysconfig; print(sysconfig.get_path("purelib"))'))
        abi = f'cp{version[0]}{version[1]}'
        packages = []
        for package in profile['packages']:
            wheel = next((x for x in package['wheels'] if f'{abi}-{abi}-' in x['filename'] or 'py3-none-any' in x['filename']), None)
            if not wheel:
                raise ValueError('No locked wheel for this Python ABI.')
            packages.append(wheel)
    fingerprint = hashlib.sha256(json.dumps(profile, sort_keys=True).encode()).hexdigest()
    stamp = private / 'python-profile.sha256'
    if stamp.exists() and stamp.read_text().strip() != fingerprint:
        raise ValueError('Python dependency profile changed. Recreate .hpm/python explicitly.')
    if not stamp.exists():
        site.mkdir(parents=True, exist_ok=True)
        for package in packages:
            extract(artifact(package, private), site)
        if WINDOWS:
            write(target / profile['pth'], profile['stdlib'] + '\n.\nLib/site-packages\n')
            shutil.copyfile(executable, target / 'python3.exe')
        write(stamp, fingerprint + '\n')
    code = 'import json,importlib.metadata as m; print(json.dumps({p:m.version(p) for p in ["PyYAML","Jinja2","MarkupSafe"]}))'
    installed = json.loads(run(executable, '-I', '-c', code))
    if installed != {p['name']: p['version'] for p in profile['packages']}:
        raise ValueError('Private Python packages differ from lock.')
    return executable


def install(args):
    if platform.machine().lower() not in ('x86_64', 'amd64') or sys.platform not in ('win32', 'linux'):
        raise ValueError('Supported hosts: Windows x64 and Linux x86_64.')
    project = Path(args.project).resolve()
    if not (project / 'CMakeLists.txt').is_file():
        raise ValueError('--project must contain the firmware CMakeLists.txt.')
    for tool in ('cmake', 'ninja', 'git'):
        if not shutil.which(tool):
            raise ValueError(f'Missing host tool: {tool}')
    version = tuple(map(int, re.search(r'(\d+\.\d+\.\d+)', run('cmake', '--version'))[1].split('.')))
    if version < (3, 24, 0):
        raise ValueError('CMake 3.24+ required.')
    profile = read(ROOT / 'hpm-lock.json')
    lock_path = project / 'hpm-lock.json'
    if lock_path.exists():
        lock = read(lock_path)
        if lock.get('schema') == 1:
            lock = migrate(project, lock, profile)
        if lock.get('schema') != 2 or lock['wrapper']['version'] != (ROOT / 'VERSION').read_text().strip():
            raise ValueError('Installer version differs from project lock. Use its pinned release.')
        if not (project / 'CMakePresets.json').is_file():
            raise ValueError('Restore CMakePresets.json from Git alongside hpm-lock.json.')
        print('Restoring local environment from hpm-lock.json; project configuration unchanged.', flush=True)
    else:
        lock = first_import(args, project, profile)
    private = project / '.hpm'
    private.mkdir(exist_ok=True)
    local_file = private / 'local.json'
    local = read(local_file) if local_file.exists() else {}
    current = lock['platforms'][HOST]
    selected = {}
    for name, explicit in (('sdk', args.sdk_root), ('toolchain', args.toolchain_root)):
        source = Path(explicit).resolve() if explicit else Path(local.get(name, private / name))
        if not source.exists():
            if explicit:
                raise ValueError(f'Missing explicit {name} path: {source}')
            source = private / name
            if source.is_symlink():
                raise ValueError(f'Stale local link: {source}. Remove only the link before restoring.')
            staging_root = private / 'staging'
            staging_root.mkdir(exist_ok=True)
            with tempfile.TemporaryDirectory(dir=staging_root) as temporary:
                staging = Path(temporary)
                if name == 'sdk':
                    payload = staging / 'sdk'
                    run('git', 'init', '-q', payload)
                    run('git', '-C', payload, 'config', 'core.longpaths', 'true')
                    run('git', '-C', payload, 'config', 'core.autocrlf', 'false')
                    run('git', '-C', payload, 'remote', 'add', 'origin', lock['sdk']['url'])
                    run('git', '-C', payload, 'fetch', '--depth', '1', 'origin', lock['sdk']['commit'])
                    run('git', '-C', payload, 'checkout', '--detach', lock['sdk']['commit'])
                else:
                    extract(artifact(current['toolchain'], private), staging)
                    payload = staging / current['toolchain']['archiveRoot']
                payload.rename(source)
        selected[name] = str(source.resolve())
    sdk = Path(selected['sdk'])
    archive_asserted = False
    if not (sdk / '.git').exists():
        archive_asserted = bool(args.sdk_revision and revision(args.sdk_revision, lock['sdk']['url']) == lock['sdk']['commit']) or (local.get('sdk') == str(sdk) and local.get('archiveVersionSha256') == sha(sdk / 'VERSION'))
    validate_sdk(sdk, lock, archive_asserted)
    validate_gcc(Path(selected['toolchain']), current['toolchain'])
    python = prepare_python(private, current['python'])
    for name in ('hpm-project-hook.cmake', 'hpm-sdk-compat.cmake'):
        target = private / 'cmake' / name
        target.parent.mkdir(exist_ok=True)
        shutil.copyfile(ROOT / 'cmake' / name, target)
    env = {'HPM_SDK_BASE': sdk.as_posix(), 'GNURISCV_TOOLCHAIN_PATH': Path(selected['toolchain']).as_posix(), 'HPM_SDK_TOOLCHAIN_VARIANT': 'gcc'}
    write(private / 'environment.json', {'version': 5, 'configurePresets': [{'name': 'hpm-local', 'hidden': True, 'environment': env, 'cacheVariables': {'python_exec': {'type': 'FILEPATH', 'value': python.as_posix()}, 'CMAKE_PROJECT_INCLUDE': '${sourceDir}/.hpm/cmake/hpm-project-hook.cmake'}}]})
    selected.update(python=str(python), platform=HOST, lockSha256=sha(lock_path))
    if archive_asserted:
        selected['archiveVersionSha256'] = sha(sdk / 'VERSION')
    write(local_file, selected)
    write(private / 'synced-lock.sha256', sha(lock_path) + '\n')
    shutil.copyfile(ROOT / 'templates/activate.ps1', private / 'activate.ps1')
    template = (ROOT / 'templates/activate.sh').read_text()
    import shlex
    for key, value in {'SDK': str(sdk), 'GCC': selected['toolchain'], 'PYTHON_BIN': str(python.parent), 'PROJECT': str(project)}.items():
        template = template.replace('@' + key + '@', shlex.quote(value))
    write(private / 'activate.sh', template)
    ignore_path = project / '.gitignore'
    existing = ignore_path.read_text() if ignore_path.exists() else ''
    additions = [x for x in ('/.hpm/', '/build/', '/.hpm-cmake-install-*/', '/.hpm-cmake/', '/activate.ps1', '/CMakeUserPresets.json') if x not in existing.splitlines()]
    if additions:
        write(ignore_path, existing + '\n# Generated local environment (restore with the installer)\n' + '\n'.join(additions) + '\n')
    print('Ready. / 环境已就绪：', flush=True)
    print('  .\\.hpm\\activate.ps1' if WINDOWS else '  source .hpm/activate.sh')
    print('  cmake --preset default\n  cmake --build --preset default --parallel')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', default='.')
    for name in ('build-directory', 'sdk-root', 'toolchain-root', 'sdk-revision'):
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
