import {V86} from './assets/libv86.mjs';

const MAX_TRANSFER = 16 * 1024 * 1024;
const PHYSICAL_MAILBOX = 192 * 1024 * 1024;
let emulator, pending, booted = false, mailbox, mailboxToken;
let traceMessages = false, partial = '', log = '';
const encoder = new TextEncoder();
const jsonDecoder = new TextDecoder('utf-8', {fatal: true});
const parentClock = new BigInt64Array(new SharedArrayBuffer(8));
const clockBytes = new Uint8Array(8);
const clockView = new DataView(clockBytes.buffer);
function updateClock() {
  clockView.setFloat64(0, Number(Atomics.load(parentClock, 0)) / 1000, true);
  emulator.write_memory(clockBytes, PHYSICAL_MAILBOX + 168);
}
function send(text) { updateClock(); emulator.serial0_send(text); }
function mailboxRead(offset, lengthIndex, capacity) {
  const header = emulator.read_memory(mailbox + 128, 16);
  const length = new DataView(header.buffer, header.byteOffset, 16).getUint32(lengthIndex * 4, true);
  if (length > capacity) throw new Error('Invalid mailbox length');
  return emulator.read_memory(mailbox + offset, length).slice();
}
function mailboxWrite(offset, lengthIndex, capacity, bytes) {
  if (bytes.length > capacity) throw new Error('Host mailbox overflow');
  emulator.write_memory(bytes, mailbox + offset);
  const length = new Uint8Array(4);
  new DataView(length.buffer).setUint32(0, bytes.length, true);
  emulator.write_memory(length, mailbox + 128 + lengthIndex * 4);
}
function acceptMailbox() {
  const token = encoder.encode(mailboxToken);
  const actual = emulator.read_memory(PHYSICAL_MAILBOX, token.length);
  if (!token.every((byte, i) => actual[i] === byte)) throw new Error('Guest mailbox token mismatch');
  mailbox = PHYSICAL_MAILBOX;
  self.postMessage({type: 'clock', buffer: parentClock.buffer, offset: 0});
  setInterval(updateClock, 1);
}
function fail(error) {
  self.postMessage({type: 'failed', error: String(error?.stack || error), log});
}

async function overlayArchive(config, app) {
  const parts = [];
  for (const [name, data] of [
    ['nupp/entropy.bin', crypto.getRandomValues(new Uint8Array(32))],
    ['host/config.json', encoder.encode(JSON.stringify(config))],
    ['host/app.lua', app],
    ['TRAILER!!!', new Uint8Array()],
  ]) {
    const filename = encoder.encode(name + '\0');
    const fields = [1, 0o100400, 0, 0, 1, 0, data.length, 0, 0, 0, 0, filename.length, 0];
    const header = encoder.encode('070701' + fields.map(n => n.toString(16).padStart(8, '0')).join(''));
    parts.push(header, filename, new Uint8Array((4 - (header.length + filename.length) % 4) % 4),
      data, new Uint8Array((4 - data.length % 4) % 4));
  }
  return await new Response(new Blob(parts).stream().pipeThrough(new CompressionStream('gzip'))).arrayBuffer();
}

// SHARED_LINE_PROTOCOL

async function boot(message) {
  if (booted) throw new Error('VM was already booted');
  booted = true;
  traceMessages = message.config.traceRequires === true;
  mailboxToken = 'NUPP_MAILBOX_' + [...crypto.getRandomValues(new Uint8Array(32))].map(n => n.toString(16).padStart(2, '0')).join('');
  if (!self.crossOriginIsolated) throw new Error('Spike clock requires cross-origin isolation');
  const [initrd, app] = await Promise.all(['./initramfs.gz', message.appUrl].map(async url => {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`Cannot fetch ${url}: ${response.status}`);
    return new Uint8Array(await response.arrayBuffer());
  }));
  const seeded = await new Blob([initrd, await overlayArchive({...message.config, mailboxToken}, app)]).arrayBuffer();
  emulator = new V86({
    wasm_path: new URL('./assets/v86.wasm', import.meta.url).href,
    memory_size: 256 * 1024 * 1024, vga_memory_size: 1024 * 1024,
    bios: {url: new URL('./assets/seabios.bin', import.meta.url).href},
    vga_bios: {url: new URL('./assets/vgabios.bin', import.meta.url).href},
    bzimage: {url: new URL('./assets/bzimage.bin', import.meta.url).href},
    initrd: {buffer: seeded},
    cmdline: 'console=ttyS0,115200 quiet rdinit=/init mem=192M iomem=relaxed tsc=reliable random.trust_cpu=on' +
      (message.config.mode === 'features' ? '' : ' nupp.bridge=1'),
    autostart: true, disable_speaker: true, disable_mouse: true, disable_keyboard: true,
  });
  emulator.add_listener('download-error', error => fail(new Error('v86 download failed: ' + JSON.stringify(error))));
  emulator.add_listener('serial0-output-byte', byte => {
    const text = String.fromCharCode(byte);
    log = (log + text).slice(-16000);
    if (text === '\r') return;
    if (text !== '\n') { partial += text; return; }
    if (mailbox === undefined || traceMessages) self.postMessage({type: 'log', log});
    const line = partial; partial = '';
    try {
      lineReceived(line);
      if (message.config.mode === 'features' && line.includes('@@NUPP_QEMU_READY@@')) self.postMessage({type: 'ready'});
      if (message.config.mode === 'features' && line === '@@NUPP_QEMU_EXIT@@ 0') {
        const passed = (log.match(/@@NUPP_QEMU@@\tPASS\t/g) || []).length;
        if (passed !== 12 || log.includes('@@NUPP_QEMU@@\tFAIL\t')) throw new Error('Missing feature checks');
        self.postMessage({type: 'done', result: {ok: true, value: {passed, log,
          wasmMemoryBytes: emulator.v86.cpu.wasm_memory.buffer.byteLength}}});
      }
    } catch (error) { fail(error); }
  });
}

// SHARED_RESPONSE_PROTOCOL
