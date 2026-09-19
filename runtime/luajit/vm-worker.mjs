import {V86} from './assets/libv86.mjs';
import {loadManifest, assetsFor} from './assets.mjs';
const MIB = 1024 * 1024;
const encoder = new TextEncoder(), decoder = new TextDecoder('utf-8', {fatal: true});
let emulator, mailbox, active, sequence = 0, log = '', line = '', timer, booted = false;
function fail(error) {
  clearInterval(timer);
  self.postMessage({type: 'failed', error: String(error?.stack || error), log});
}
function clock() {
  const bytes = new Uint8Array(8);
  new DataView(bytes.buffer).setFloat64(0, performance.now(), true);
  emulator.write_memory(bytes, mailbox + 168);
}
function send(text) { clock(); emulator.serial0_send(text); }
function read() {
  const bytes = emulator.read_memory(mailbox + 128, 4);
  const length = new DataView(bytes.buffer, bytes.byteOffset, 4).getUint32(0, true);
  if (length > MIB) throw new Error('Guest result exceeds mailbox');
  return JSON.parse(decoder.decode(emulator.read_memory(mailbox + 4096, length)));
}
function write(offset, index, capacity, bytes) {
  if (!(bytes instanceof Uint8Array) || bytes.length > capacity) throw new Error('Host input exceeds mailbox');
  emulator.write_memory(bytes, mailbox + offset);
  const size = new Uint8Array(4);
  new DataView(size.buffer).setUint32(0, bytes.length, true);
  emulator.write_memory(size, mailbox + 128 + index * 4);
}
async function boot(message) {
  if (booted) throw new Error('Worker has already booted');
  booted = true;
  const base = new URL(message.manifestUrl, import.meta.url).href;
  const manifest = await loadManifest(base);
  const profile = message.profile === 'compiler' ? 'compiler' : 'runner';
  const memoryMiB = manifest.profiles?.[profile]?.memoryMiB;
  if (memoryMiB !== (profile === 'compiler' ? 128 : 64)) throw new Error('Unsupported guest memory profile');
  mailbox = (memoryMiB - 16) * MIB;
  const asset = assetsFor(manifest, base);
  const app = new Uint8Array(message.app);
  const config = encoder.encode(JSON.stringify(message.config || {}));
  if (!app.length || app.length > 7 * MIB || !config.length || config.length > 65536) throw new Error('Startup input exceeds mailbox');
  let snapshot;
  const selected = manifest.snapshots?.[profile];
  if (selected && message.snapshot !== false && !message.captureSnapshot) {
    try {
      if (selected.buildKey !== manifest.buildKey || selected.memoryMiB !== memoryMiB || selected.guestAbi !== manifest.guestAbi) {
        throw new Error('Snapshot does not match the guest build/profile');
      }
      const packed = await asset(selected.asset);
      snapshot = await new Response(new Blob([packed]).stream().pipeThrough(new DecompressionStream('gzip'))).arrayBuffer();
      if (snapshot.byteLength !== selected.uncompressedBytes || snapshot.byteLength > 256 * MIB) throw new Error('Invalid snapshot extent');
    } catch (error) {
      self.postMessage({type: 'snapshot-fallback', reason: String(error.message)});
    }
  }
  const wasm = await asset('assets/v86.wasm');
  const options = {
    memory_size: memoryMiB * MIB, vga_memory_size: MIB,
    disable_speaker: true, disable_mouse: true, disable_keyboard: true,
    autostart: !snapshot,
    wasm_fn: async imports => {
      try { return (await WebAssembly.instantiate(wasm, imports)).instance.exports; }
      catch (error) {
        if (!(error instanceof WebAssembly.CompileError)) throw error;
        return (await WebAssembly.instantiate(await asset('assets/v86-fallback.wasm'), imports)).instance.exports;
      }
    },
  };
  if (snapshot) options.initial_state = {buffer: snapshot};
  else {
    const [bios, vga, kernel, initrd] = await Promise.all(['assets/bios.bin', 'assets/vgabios.bin', 'assets/bzimage.bin', 'assets/initramfs.gz'].map(asset));
    Object.assign(options, {bios: {buffer: bios.buffer}, vga_bios: {buffer: vga.buffer},
      bzimage: {buffer: kernel.buffer}, initrd: {buffer: initrd.buffer},
      cmdline: `console=ttyS0,115200 earlyprintk=serial,ttyS0,115200 rootfstype=ramfs rdinit=/init mem=${memoryMiB - 16}M iomem=relaxed tsc=reliable random.trust_cpu=on nupp.mailbox=${mailbox}`});
  }
  const start = () => {
    const header = new Uint8Array(24), now = Date.now();
    [0x5350554e, 1, config.length, app.length, Math.floor(now / 1000), now % 1000 * 1000]
      .forEach((value, index) => new DataView(header.buffer).setUint32(index * 4, value, true));
    emulator.write_memory(header, mailbox);
    emulator.write_memory(crypto.getRandomValues(new Uint8Array(32)), mailbox + 512);
    emulator.write_memory(config, mailbox + 4096);
    emulator.write_memory(app, mailbox + MIB);
    emulator.serial0_send('start\n');
    if (snapshot) emulator.run();
  };
  emulator = new V86(options);
  emulator.add_listener('emulator-loaded', () => { if (snapshot) start(); });
  emulator.add_listener('serial0-output-byte', byte => {
    const char = String.fromCharCode(byte);
    log = (log + char).slice(-16384);
    if (char === '\r') return;
    if (char !== '\n') { line = (line + char).slice(-16384); return; }
    const current = line; line = '';
    self.postMessage({type: 'log', log});
    try {
      if (current.includes('Kernel panic - not syncing:') || current.startsWith('Failed to execute /init')) throw new Error(current);
      if (current === '@@NUPP_SNAPSHOT_READY@@') {
        if (message.captureSnapshot) {
          (async () => {
            await emulator.stop();
            const state = await emulator.save_state();
            self.postMessage({type: 'snapshot', state, buildKey: manifest.buildKey, memoryMiB}, [state]);
          })().catch(fail);
        } else start();
      } else if (current === '@@NUPP_MAILBOX@@ 0') {
        timer = setInterval(clock, 1);
        send('mailbox\n');
        self.postMessage({type: 'ready', wasmMemoryBytes: emulator.v86.cpu.wasm_memory.buffer.byteLength});
      } else {
        const match = current.match(/^@@NUPP_(COMPILER|EFFECT|DONE)@@ (\d+)$/);
        if (!match) return;
        const incoming = Number(match[2]);
        if (incoming !== sequence || active) throw new Error('Unexpected guest frame sequence');
        active = match[1] !== 'DONE';
        self.postMessage({type: match[1].toLowerCase(), sequence, result: read()});
      }
    } catch (error) { fail(error); }
  });
}
self.onmessage = ({data}) => {
  try {
    if (data.type === 'boot') { boot(data).catch(fail); return; }
    if (data.type !== 'response' || !active || data.sequence !== sequence) throw new Error('Stale host response');
    write(4 * MIB, 2, MIB, encoder.encode(JSON.stringify(data.response)));
    write(5 * MIB, 3, 2 * MIB, new Uint8Array(data.payload || new ArrayBuffer(0)));
    active = false;
    send(String(sequence++) + '\n');
  } catch (error) { fail(error); }
};
self.addEventListener('unhandledrejection', event => { event.preventDefault(); fail(event.reason); });
