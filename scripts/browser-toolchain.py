#!/usr/bin/env python3
"""Provision browser inputs through scripts/toolchain.pins, including offline builds."""
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import shlex
import importlib.util
import shutil
from string import Template
import subprocess
import sys
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with open(path, 'rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def pins():
    values = {}
    for line in (ROOT / 'scripts/toolchain.pins').read_text().splitlines():
        if line and not line.startswith('#') and '=' in line:
            key, value = line.split('=', 1)
            values[key] = Template(shlex.split(value)[0]).substitute(values)
    return values


@contextmanager
def lock(path):
    until = time.monotonic() + 600
    while True:
        try:
            path.mkdir(parents=True)
            break
        except FileExistsError:
            if time.monotonic() > until:
                raise RuntimeError(f'timed out waiting for {path}; inspect the owning build before removing it')
            time.sleep(.2)
    try:
        yield
    finally:
        path.rmdir()


def archive(cache, record):
    target = cache / 'archives' / record['archive']
    target.parent.mkdir(parents=True, exist_ok=True)
    with lock(target.with_suffix(target.suffix + '.lock')):
        if target.exists() and digest(target) == record['sha256']:
            return target
        supplied = Path(os.environ.get('NUPP_HOST_SOURCE_DIR', '/nonexistent')) / target.name
        offline = os.environ.get('NUPP_HOST_OFFLINE', '').lower()
        if offline not in ('', '0', 'false', 'no', 'off', '1', 'true', 'yes', 'on'):
            raise ValueError('invalid NUPP_HOST_OFFLINE value')
        with tempfile.TemporaryDirectory(dir=target.parent) as tmp:
            staged = Path(tmp) / target.name
            if supplied.is_file():
                shutil.copyfile(supplied, staged)
            elif offline in ('1', 'true', 'yes', 'on'):
                raise RuntimeError(f'{target.name} is not cached; supply it in NUPP_HOST_SOURCE_DIR')
            else:
                mirror = os.environ.get('NUPP_HOST_SOURCE_BASE_URL')
                url = mirror.rstrip('/') + '/' + target.name if mirror else record['url']
                subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error', url, '-o', str(staged)], check=True)
            if digest(staged) != record['sha256']:
                raise RuntimeError(f'digest mismatch for {target.name}; refusing to extract it')
            staged.replace(target)
    return target


def extract(archive_path, destination, record):
    with lock(destination.with_name(destination.name + '.lock')):
        if (destination / record['marker']).is_file() and (destination / '.pinned-source').read_text() == record['sha256']:
            return destination
        if destination.exists():
            raise RuntimeError(f'incomplete source tree {destination}; inspect it before rebuilding')
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=destination.parent) as tmp:
            with tarfile.open(archive_path) as source:
                # data_filter rejects traversal, links escaping the extraction tree,
                # devices and permission bits that do not belong in source archives.
                source.extractall(tmp, filter='data')
            staged = Path(tmp) / record['directory']
            if not (staged / record['marker']).is_file():
                raise RuntimeError(f'missing expected source marker {record["marker"]}')
            (staged / '.pinned-source').write_text(record['sha256'])
            staged.replace(destination)
    return destination


def inputs(cache):
    values = pins()
    result = {}
    for name, prefix in [('linux', 'BROWSER_LINUX'), ('musl', 'BROWSER_MUSL'), ('seabios', 'BROWSER_SEABIOS'),
                         ('v86', 'BROWSER_V86'), ('libunwind', 'BROWSER_LIBUNWIND'), ('luajit', 'LUAJIT'), ('lpeg', 'LPEG')]:
        record = {key.lower(): values[prefix + '_' + key] for key in ['URL', 'SHA256', 'DIRECTORY', 'MARKER']}
        record['archive'] = values.get(prefix + '_ARCHIVE', record['directory'] + '.tar.gz')
        record['version'] = values.get(prefix + '_VERSION', values.get(prefix + '_REV'))
        path = archive(cache, record)
        tree = cache / 'browser-sources' / (name + '-' + record['sha256'])
        tree.parent.mkdir(parents=True, exist_ok=True)
        extract(path, tree, record)
        result[name] = {**record, 'archivePath': str(path), 'sourcePath': str(tree)}
    notices = {
        'linux': [('COPYING', 'Linux-COPYING.txt'), ('LICENSES/preferred/GPL-2.0', 'Linux-GPL-2.0.txt'),
                  ('LICENSES/exceptions/Linux-syscall-note', 'Linux-syscall-note.txt')],
        'musl': [('COPYRIGHT', 'musl-COPYRIGHT.txt')],
        'libunwind': [('LICENSE.TXT', 'LLVM-libunwind-LICENSE.txt')],
        'seabios': [('COPYING', 'SeaBIOS-COPYING.txt'), ('COPYING.LESSER', 'SeaBIOS-COPYING.LESSER.txt')],
        'v86': [('LICENSE', 'v86-LICENSE.txt')],
        'luajit': [('COPYRIGHT', 'LuaJIT-COPYRIGHT.txt')],
        'lpeg': [('lpeg.html', 'LPeg-LICENSE.txt')],
    }
    for name, files in notices.items():
        for source, notice in files:
            content = (Path(result[name]['sourcePath']) / source).read_bytes()
            expected = ROOT / 'host/notices' / notice
            if name == 'lpeg':
                for clause in (b'2007-2023 Lua.org, PUC-Rio', b'Permission is hereby granted', b'THE SOFTWARE IS PROVIDED'):
                    if clause not in content or clause not in expected.read_bytes():
                        raise RuntimeError(f'{notice} differs from the pinned source')
                continue
            if expected.read_bytes() != content:
                raise RuntimeError(f'{notice} differs from the pinned source; review its license before updating the notice')
    return result


def main():
    if sys.version_info < (3, 12):
        raise RuntimeError('browser tooling requires Python 3.12 or later; select it with NUPP_PYTHON')
    sys.modules['browser_toolchain'] = sys.modules[__name__]
    command, cache = sys.argv[1], Path(sys.argv[2])
    sources = inputs(cache)
    if command == 'browser-sources':
        print(json.dumps(sources, indent=2))
    elif command == 'browser-emulator':
        print(sources['v86']['sourcePath'])
    elif command == 'browser-guest':
        spec = importlib.util.spec_from_file_location('browser_guest', ROOT / 'scripts/browser-guest.py')
        builder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(builder)
        print(builder.build(ROOT, cache, sources))
    else:
        raise ValueError('unknown browser toolchain component')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit('browser toolchain: ' + str(error))
