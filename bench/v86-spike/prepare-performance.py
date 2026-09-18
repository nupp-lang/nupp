"""Stage isolated compiler and delivery probes from the preserved memory profiles."""
from pathlib import Path
import hashlib
import json
import shutil

root = Path(__file__).resolve().parents[2]
build = root / 'build/v86-spike'
source = root / 'bench/v86-spike'
web = build / 'performance/web'
shutil.copytree(build / 'memory-128/web', web, dirs_exist_ok=True)
smoke = (root / 'tests/portable-compiler/smoke.lua').read_text()
fixture = (source / 'compiler-performance.lua').read_text().replace('-- SMOKE_CORPUS', smoke)
(web / 'compiler-performance.lua').write_text(fixture)
integration = (web / 'integration.mjs').read_text().replace('./compiler-memory.lua', './compiler-performance.lua')
integration = integration.replace("jit: !query.has('no-jit')", "jit: !query.has('no-jit'), reuseSession: query.has('reuse'), nativeBit: query.has('native-bit'), phases: query.has('phases'), profile: query.has('profile'), rounds: Number(query.get('rounds') || 1)")
integration = integration.replace("config: {mode: selected,", "config: {mode: selected, slim: query.has('slim'),")
(web / 'integration.mjs').write_text(integration)
worker = (web / 'vm-worker.mjs').read_text().replace("new URL('./assets/bzimage.bin', import.meta.url)", "new URL(message.config.slim ? './assets/kernel-empty-rootfs.bin' : './assets/bzimage.bin', import.meta.url)")
(web / 'vm-worker.mjs').write_text(worker)
candidate = build / 'performance/kernel-empty-rootfs.bin'
if candidate.exists(): shutil.copyfile(candidate, web / 'assets/kernel-empty-rootfs.bin')
profile = build / 'performance/native-bit-profile.json'
if profile.exists():
    requests = json.loads(profile.read_text())['requests']
    # The standalone probe encoder does not share the bundle's array marker.
    # Restore the known diagnostics-array shape for response comparison.
    for entry in requests:
        if isinstance(entry.get('response'), dict) and entry['response'].get('diagnostics') == {}:
            entry['response']['diagnostics'] = []
    if all('input' in entry for entry in requests if not entry['name'].startswith('request:')):
        (web / 'compiler-cases.json').write_text(json.dumps([entry for entry in requests if 'input' in entry]))
for name in ['compiler-portable.mjs', 'compiler-portable.html']:
    shutil.copyfile(source / name, web / name)
bundle = root / 'build/playground/nupp-compiler.lua'
shutil.copyfile(bundle, web / 'nupp-compiler.lua')
shutil.copyfile(root / 'editors/playground/src/wasm-runtime.js', web / 'wasm-runtime.js')
(web / 'compiler-digest.txt').write_text(hashlib.sha256(bundle.read_bytes()).hexdigest())
print(web)
