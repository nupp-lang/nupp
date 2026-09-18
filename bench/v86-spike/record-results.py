"""Retain raw conformance, paired measurements, asset hashes, and provenance."""
from pathlib import Path
import datetime
import hashlib
import json
import shutil
import subprocess

source = Path(__file__).resolve().parent
root = source.parents[1]
build = root / 'build/v86-spike'
results = source / 'results'
results.mkdir(exist_ok=True)
for group in ['conformance', 'comparison']:
    target = results / group
    target.mkdir(exist_ok=True)
    for path in (build / group).glob('*'):
        if path.suffix in ['.json', '.png']:
            shutil.copyfile(path, target / path.name)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def git(*args):
    return subprocess.check_output(['git', *args], cwd=root, text=True).strip()

assets = {str(path.relative_to(build / 'web')): {'bytes': path.stat().st_size, 'sha256': digest(path)}
          for path in sorted((build / 'web').rglob('*')) if path.is_file()}
game_files = ['assets/libv86.mjs', 'assets/v86.wasm', 'assets/bzimage.bin', 'assets/seabios.bin',
              'assets/vgabios.bin', 'initramfs.gz', 'app.ljbc', 'integration.html', 'integration.mjs',
              'guest-runtime.mjs', 'vm-worker.mjs', 'runtime/app-runtime.mjs', 'runtime/worker-pool.mjs']
inventory = {'gameAssetBytes': sum(assets[name]['bytes'] for name in game_files),
             'gameFiles': game_files,
             'scope': 'Sum of game startup files, before HTTP content encoding; initramfs is already gzip. '
                      'Excludes optional v86 fallback, unused debug/source assets, worker/native/GPU fixtures, '
                      'and the separate portable comparison host. This is not a network transfer capture.',
             'assets': assets}
(results / 'assets.json').write_text(json.dumps(inventory, indent=2) + '\n')
provenance = {
    'recordedUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'baseRevision': 'c839466f1fc05292a3ebb414a2dd0c1476ffbc09',
    'branch': git('branch', '--show-current'),
    'mainVerifiedWithoutEitherSpike': git('ls-tree', '-r', '--name-only', 'origin/main',
                                        'bench/qemu-wasm-spike', 'bench/v86-spike') == '',
    'verifiedOriginMain': git('rev-parse', 'origin/main'),
    'cpu': subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip(),
    'macOS': subprocess.check_output(['sw_vers', '-productVersion'], text=True).strip(),
    'browser': 'Chrome 152 headless; exact user agent in each result. 1000x900 CSS pixels, scale 1.',
    'method': 'Fresh Chrome per fixture; conformance modes sequential. Comparison has three alternating '
              'v86/portable pairs with no other spike test running. Same Nupp simulation, compiler revision, '
              'Canvas, input/audio oracle and 120-frame protocol. Localhost, unthrottled; exploratory, '
              'no confidence interval, mobile-browser or physical-speaker claim.',
    'guest': 'Unmodified pinned LuaJIT 2.1.1785763465; native i386 Linux, musl 1.2.5-r3. '
             '256 MiB emulated RAM, of which 64 MiB is reserved for the host mailbox. '
             'Wasm allocation in results excludes JS, browser, compiled-code and GPU memory.',
    'build': 'macOS Apple clang i386 cross-build; Emscripten 6.0.8 Wasm32 buildvm under Node; '
             'host LuaJIT generates non-GC64 bytecode with loadfile mode tW and deterministic stripped dump.',
    'sourceSha256': {str(path.relative_to(root)): digest(path) for path in sorted(source.glob('*'))
                     if path.is_file() and path.suffix in ['.py', '.mjs', '.lua', '.c', '.sh', '.json']},
    'portable': json.loads((root / 'build/qemu-wasm-spike/portable-provenance.json').read_text()),
}
(results / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
print(json.dumps({'gameAssetBytes': inventory['gameAssetBytes'], 'originMain': provenance['verifiedOriginMain']}))
