"""Retain the measured performance follow-up, without generated VM binaries."""
from pathlib import Path
import hashlib
import json
import platform
import shutil
import statistics
import subprocess

root = Path(__file__).resolve().parents[2]
source = root / 'build/v86-spike/performance'
output = root / 'bench/v86-spike/results/performance'
output.mkdir(parents=True, exist_ok=True)

def read(name):
    return json.loads((source / name).read_text())

def median(values):
    return statistics.median(values)

compiler = read('compiler-pairs/summary.json')
rows = []
for backend in ['v86-jit', 'v86-interpreter', 'lua51']:
    runs = [entry['result'] for entry in compiler if entry['backend'] == backend]
    assert len(runs) == 2 and all(entry['ok'] for entry in runs)
    if backend == 'lua51':
        rounds = [entry['rounds'] for entry in runs]
        boot = [entry['boot']['totalMs'] for entry in runs]
    else:
        assert all(entry['responsesMatchNativeAndLua51'] for entry in runs)
        rounds = []
        for entry in runs:
            requests = [request for request in entry['compiler']['value']['requests'] if request.get('input')]
            assert len(requests) == 21
            rounds.append([requests[index:index + 7] for index in range(0, 21, 7)])
        boot = [entry['compiler']['metrics']['bootMs'] + entry['compiler']['value']['loadMs'] for entry in runs]
    rows.append({
        'backend': backend,
        'bootAndBundleMsMedian': median(boot),
        'coldRequestsMsMedian': median(sum(request['ms'] for request in run[0]) for run in rounds),
        'warmRequestsMsMedian': median(sum(request['ms'] for request in round) for run in rounds for round in run[1:]),
        'coldPlatformCompileMsMedian': median(run[0][4]['ms'] for run in rounds),
        'warmPlatformCompileMsMedian': median(round[4]['ms'] for run in rounds for round in run[1:]),
    })
delivery = []
for label, count in [('local', 2), ('10mbps', 1)]:
    samples = read(f'delivery-{label}/summary.json')
    assert len(samples) == count * 6
    for variant in ['raw', 'compressed', 'slim']:
        for visit in ['cold', 'cached']:
            selected = [entry for entry in samples if entry['variant'] == variant and entry['visit'] == visit]
            assert len(selected) == count
            payloads = {entry['delivery']['payloadBytes'] for entry in selected}
            assert len(payloads) == 1
            delivery.append({'link': label, 'variant': variant, 'visit': visit,
                'runs': count, 'payloadBytes': payloads.pop(),
                'firstFrameMsMedian': median(entry['firstFrameMs'] for entry in selected)})
summary = {'compiler': rows, 'delivery': delivery, 'kernel': read('kernel-analysis.json')}
(output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
for name in ['compiler-pairs/summary.json', 'delivery-local/summary.json', 'delivery-10mbps/summary.json',
             'kernel-analysis.json', 'native-profile.json', 'native-bit-profile.json',
             'compiler-phases.json', 'compiler-native-bit-128.json', 'compiler-assets.json',
             'slim-features.json', 'slim-native.json']:
    destination = output / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source / name, destination)
scripts = [root / 'bench/qemu-wasm-spike/run-browser.mjs', *sorted((root / 'bench/v86-spike').glob('*'))]
artifacts = [root / 'build/playground/nupp-compiler.lua', source / 'web/nupp-playground.wasm',
             root / 'build/v86-spike/memory-128/playground-compiler.ljbc']
provenance = {
    'parentRevision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'host': platform.platform(),
    'compilerMethod': 'Two alternating fresh-Chrome runs per backend, three corpus rounds per retained session. Exact response comparison to the same native fixture; v86 hash known answers. Request times use the parent browser clock (coarse in guest), excluding serial progress prints and boot. Lua 5.1 includes its existing JSON request ABI. Warm rounds repeat the same sources, not an editing stress test. No machine isolation or confidence interval claim.',
    'diagnosticScope': 'The exploratory native profiles, phase OOM result, and native-bit first pass preceded final harness fields and paired runs. Source hashes below describe the final reproducible harness; those earlier diagnostics are not paired speed measurements.',
    'deliveryMethod': 'Two alternating local pairs and one illustrative link-model pair. Cold Chrome profile then fresh Chrome process reusing its disk cache. Completed HTTP body bytes from server, excluding protocol headers. Rate model: aggregate 1250000 bytes/s and 80 ms first-byte delay per request; not a real WAN measurement. Game correctness and input/audio/Canvas assertions pass on every visit.',
    'kernelMethod': 'Diagnostic removal of the embedded filesystem, preserving ELF addresses and extents with gzip header padding. Booted successfully. A shipping implementation must build a minimal kernel from source; no binary distribution or licensing-compliance package is produced here.',
    'sourceSha256': {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                     for path in scripts if path.is_file()},
    'artifactSha256': {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in artifacts},
}
(output / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
print(json.dumps({'compiler': rows, 'delivery': delivery}, indent=2))
