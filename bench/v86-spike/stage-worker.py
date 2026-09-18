"""Reuse the tested QEMU mailbox validation with v86's physical-memory API."""
from pathlib import Path

source = Path(__file__).resolve().parent
original = (source.parent / 'qemu-wasm-spike/vm-worker.mjs').read_text()
lines = original[original.index('function lineReceived('):original.index('async function boot(')]
start = lines.index("  if (line === '@@NUPP_MAILBOX@@') {")
end = lines.index('  const request = ', start)
lines = lines[:start] + "  if (line === '@@NUPP_MAILBOX@@') acceptMailbox();\n" + lines[end:]
lines = lines.replace("{type: 'done', result:", "{type: 'done', wasmMemoryBytes: emulator.v86.cpu.wasm_memory.buffer.byteLength, result:")
response = original[original.index("self.addEventListener('message'"):]
target = source.parents[1] / 'build/v86-spike/web/vm-worker.mjs'
target.write_text((source / 'vm-worker.mjs').read_text()
                  .replace('// SHARED_LINE_PROTOCOL', lines)
                  .replace('// SHARED_RESPONSE_PROTOCOL', response))
