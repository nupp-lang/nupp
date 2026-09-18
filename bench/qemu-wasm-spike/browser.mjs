import { openpty } from './assets/xterm-pty.mjs';
import init from './assets/out.js';

const result = document.querySelector('#result');
const terminal = document.querySelector('#terminal');
const started = window.spikeStarted;
const { master, slave } = openpty();
const decoder = new TextDecoder();
let send;
let finished = false;
let output = '';
let guestReadyMs;
let testsStartedMs;
const expected = ['bit', 'ffi-array-pointer', 'ffi-int64', 'ffi-libc', 'ffi-load', 'ffi-callback',
  'string-buffer', 'buffer-serialization', 'jit-trace', 'nupp-struct', 'jit-on-off-correctness'];

async function entropyArchive() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const encoder = new TextEncoder();
  const parts = [];
  for (const [name, mode, data] of [['nupp/entropy.bin', 0o100400, bytes], ['TRAILER!!!', 0, new Uint8Array()]]) {
    const filename = encoder.encode(name + '\0');
    const fields = [1,mode,0,0,1,0,data.length,0,0,0,0,filename.length,0];
    const header = encoder.encode('070701' + fields.map(value => value.toString(16).padStart(8, '0')).join(''));
    parts.push(header, filename, new Uint8Array((4 - (header.length + filename.length) % 4) % 4), data,
      new Uint8Array((4 - data.length % 4) % 4));
  }
  const stream = new Blob(parts).stream().pipeThrough(new CompressionStream('gzip'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

function finish(exitCode) {
  if (finished) return;
  finished = true;
  const clean = output.replaceAll('\r', '');
  const events = clean.split('\n').filter(line => line.startsWith('@@NUPP_QEMU@@\t'))
    .map(line => { const [,kind,name,detail] = line.split('\t'); return {kind,name,detail}; });
  const checks = events.filter(event => event.kind === 'PASS' || event.kind === 'FAIL');
  const complete = events.some(event => event.kind === 'DONE' && event.name === 'failures' && event.detail === '0');
  const ok = exitCode === 0 && complete && expected.every(name => checks.some(event => event.name === name && event.kind === 'PASS'))
    && !checks.some(event => event.kind === 'FAIL');
  const measured = events.filter(event => event.kind === 'BENCH').map(event => {
    const [elapsedMs,sample,steps] = event.detail.split(',').map(Number);
    return {jit:event.name,elapsedMs,sample,steps};
  });
  const resources = performance.getEntriesByType('resource').map(entry => ({
    file: new URL(entry.name).pathname, transferBytes:entry.transferSize, decodedBytes:entry.decodedBodySize,
  }));
  result.dataset.status = ok ? 'passed' : 'failed';
  result.textContent = JSON.stringify({ok, exitCode, guestReadyMs, testsStartedMs, totalMs:performance.now()-started,
    configuredWasmMemoryBytes:2411724800, guestMemoryMiB:256, events, measured, resources, output}, null, 2);
}

master.activate({
  onData(callback) { send = callback; return { dispose() {} }; },
  onBinary() { return { dispose() {} }; },
  onResize() { return { dispose() {} }; },
  write(bytes, done) {
    output += decoder.decode(bytes, { stream: true });
    terminal.textContent = output;
    done();
    const clean = output.replaceAll('\r', '').replace(/\x1b\[[0-9;?]*[A-Za-z]/g, '');
    if (guestReadyMs === undefined && clean.includes('@@NUPP_QEMU_READY@@')) {
      guestReadyMs = performance.now() - started;
      result.textContent = 'Linux ready. Testing LuaJIT and Nupp…';
    }
    if (testsStartedMs === undefined && clean.includes('@@NUPP_QEMU@@\tINFO\truntime\t')) {
      testsStartedMs = performance.now() - started;
    }
    const exit = clean.match(/\n@@NUPP_QEMU_EXIT@@ (\d+)\n/);
    if (exit) finish(Number(exit[1]));
  }
});

window.sendGuest = line => send(line + '\n');
window.guestOutput = () => output;

try {
  if (!crossOriginIsolated) throw new Error('COOP/COEP headers are required; use the provided local server.');
  const [kernel, initrd] = await Promise.all(['./assets/load-kernel.data', './initramfs.gz'].map(async url => {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`Cannot load ${url}: ${response.status}`);
    return new Uint8Array(await response.arrayBuffer());
  }));
  const seededInitrd = new Uint8Array(await new Blob([initrd, await entropyArchive()]).arrayBuffer());
  Module.pty = slave;
  Module.printErr = text => { output += text + '\n'; terminal.textContent = output; console.error(text); };
  Module.arguments = [
    '-nographic', '-M', 'pc', '-m', '256M', '-accel', 'tcg,tb-size=500', '-L', '/pack-rom/', '-nic', 'none',
    '-kernel', '/kernel', '-initrd', '/initramfs.gz',
    '-append', 'console=ttyS0 quiet rdinit=/init'
  ];
  Module.preRun.push(mod => {
    mod.FS.writeFile('/kernel', kernel);
    mod.FS.writeFile('/initramfs.gz', seededInitrd);
  });
  await init(Module);
  const oldPoll = Module.TTY.stream_ops.poll;
  Module.TTY.stream_ops.poll = (stream, timeout) => !slave.readable ? (slave.writable ? 4 : 0) : oldPoll(stream, timeout);
} catch (error) {
  result.dataset.status = 'failed';
  result.textContent = JSON.stringify({ok:false, error:String(error), output});
}
