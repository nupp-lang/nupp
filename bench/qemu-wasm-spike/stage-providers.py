"""Retarget the existing browser provider namespace inside the isolated spike.

The production catalog restricts these providers to lua51. Separate module names
let this experiment compile their same implementations for LuaJIT and select
them explicitly, without weakening production dialect checks.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
destination = root / 'build/qemu-wasm-spike/provider-src/nupp/qemu/browser'
for source in (root / 'src/nupp/runtime/browser').rglob('*.nupp'):
    relative = source.relative_to(root / 'src/nupp/runtime/browser')
    target = destination / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    text = source.read_text().replace('nupp.runtime.browser', 'nupp.qemu.browser')
    target.write_text(text)
print('Staged browser provider sources under', destination)
