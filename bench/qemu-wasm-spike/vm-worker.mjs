import {openpty} from './assets/xterm-pty.mjs';
import initialize from './assets/out.js';
import loadRoms from './assets/rom-loader.mjs';

const MAX_TRANSFER = 16 * 1024 * 1024;
let module, send, pending, booted = false;
let mailbox, mailboxToken;
let traceMessages = false;
const encoder = new TextEncoder();
function mailboxRead(offset, lengthIndex, capacity) {
  const header = new DataView(module.HEAPU8.buffer, mailbox + 128, 16);
  const length = header.getUint32(lengthIndex * 4, true);
  if (length > capacity) throw new Error('Invalid mailbox length');
  return module.HEAPU8.slice(mailbox + offset, mailbox + offset + length);
}
function mailboxWrite(offset, lengthIndex, capacity, bytes) {
  if (bytes.length > capacity) throw new Error('Host mailbox overflow');
  module.HEAPU8.set(bytes, mailbox + offset);
  new DataView(module.HEAPU8.buffer, mailbox + 128, 16).setUint32(lengthIndex * 4, bytes.length, true);
}
const decoder = new TextDecoder();
let partial = '';
let log = '';

async function entropyArchive() {
  const encoder = new TextEncoder();
  const parts = [];
  for (const [name, mode, data] of [
    ['nupp/entropy.bin', 0o100400, crypto.getRandomValues(new Uint8Array(32))],
    ['TRAILER!!!', 0, new Uint8Array()],
  ]) {
    const filename = encoder.encode(name + '\0');
    const fields = [1, mode, 0, 0, 1, 0, data.length, 0, 0, 0, 0, filename.length, 0];
    const header = encoder.encode('070701' + fields.map(n => n.toString(16).padStart(8, '0')).join(''));
    parts.push(header, filename, new Uint8Array((4 - (header.length + filename.length) % 4) % 4),
      data, new Uint8Array((4 - data.length % 4) % 4));
  }
  return new Uint8Array(await new Response(new Blob(parts).stream().pipeThrough(new CompressionStream('gzip'))).arrayBuffer());
}

function fail(error) {
  self.postMessage({type: 'failed', error: String(error?.stack || error), log});
}

function lineReceived(line) {
  if (line.includes('Kernel panic')) throw new Error(line);
  if (/^@@NUPP_QEMU_EXIT@@ [1-9]/.test(line)) throw new Error('Guest exited before completion: ' + log);
  if (line.includes('@@NUPP_BRIDGE_READY@@')) self.postMessage({type: 'ready'});
  if (line === '@@NUPP_MAILBOX@@') {
    const token = encoder.encode(mailboxToken);
    const words = new Uint32Array(module.HEAPU8.buffer);
    const first = new DataView(token.buffer).getUint32(0, true);
    let index = -1;
    while ((index = words.indexOf(first, index + 1)) >= 0) {
      const offset = index * 4;
      if (offset % 4096 === 0 && token.every((byte, i) => module.HEAPU8[offset + i] === byte)) {
        if (offset + 64 * 1024 * 1024 > module.HEAPU8.length) throw new Error('Mailbox outside QEMU heap');
        mailbox = offset; break;
      }
    }
    if (mailbox === undefined) throw new Error('Cannot locate reserved guest mailbox');
    // The clock writer must run outside the emulation Worker. A busy guest can
    // occupy this event loop; it must not also stop the clock used for deadlines.
    self.postMessage({type: 'clock', buffer: module.HEAPU8.buffer, offset: mailbox + 168});
  }
  const request = line.match(/^@@NUPP_BRIDGE_REQUEST@@ (\d+)$/);
  if (request) {
    if (pending) throw new Error('Guest sent concurrent transport frames');
    const frame = JSON.parse(decoder.decode(mailboxRead(4096, 0, 8 * 1024 * 1024)));
    if (frame.sequence !== Number(request[1])) throw new Error('Guest frame sequence mismatch');
    frame.leases = Object.values(frame.leases || {});
    const seen = new Set();
    const transfers = mailboxRead(4096 + 8 * 1024 * 1024, 1, MAX_TRANSFER);
    if (transfers.length > MAX_TRANSFER) throw new Error('Guest transfer too large');
    let total = 0;
    for (const lease of frame.leases) {
      if (!Number.isSafeInteger(lease.id) || lease.id < 1 || seen.has(lease.id) ||
          !Number.isSafeInteger(lease.bytes) || lease.bytes < 0 || (total += lease.bytes) > MAX_TRANSFER) {
        throw new Error('Invalid guest transfer lease');
      }
      seen.add(lease.id);
      if (!Number.isSafeInteger(lease.offset) || lease.offset < 0 || lease.offset + lease.bytes > transfers.length) {
        throw new Error('Guest lease out of transfer bounds');
      }
      lease.data = transfers.slice(lease.offset, lease.offset + lease.bytes).buffer;
      if (lease.data.byteLength !== lease.bytes) throw new Error('Guest lease length mismatch');
    }
    pending = frame;
    self.postMessage({type: 'effect', ...frame}, frame.leases.map(lease => lease.data));
  }
  if (line === '@@NUPP_BRIDGE_DONE@@') {
    self.postMessage({type: 'done', result: JSON.parse(decoder.decode(mailboxRead(4096, 0, 8 * 1024 * 1024))), log});
  }
}

async function boot(message) {
  if (booted) throw new Error('VM was already booted');
  booted = true;
  traceMessages = message.config.traceRequires === true;
  mailboxToken = 'NUPP_MAILBOX_' + [...crypto.getRandomValues(new Uint8Array(32))].map(n => n.toString(16).padStart(2, '0')).join('');
  if (!self.crossOriginIsolated) throw new Error('QEMU requires cross-origin isolation');
  const {master, slave} = openpty();
  master.activate({
    onData(callback) { send = callback; return {dispose() {}}; },
    onBinary() { return {dispose() {}}; },
    onResize() { return {dispose() {}}; },
    write(bytes, done) {
      const text = decoder.decode(bytes, {stream: true});
      log = (log + text).slice(-16000);
      if (mailbox === undefined || traceMessages) self.postMessage({type: 'log', log});
      partial += text.replaceAll('\r', '');
      done();
      try {
        let newline;
        while ((newline = partial.indexOf('\n')) >= 0) {
          const line = partial.slice(0, newline); partial = partial.slice(newline + 1);
          lineReceived(line);
        }
      } catch (error) { fail(error); }
    },
  });
  const [kernel, initrd, app] = await Promise.all([
    './assets/load-kernel.data', './initramfs.gz', message.appUrl,
  ].map(async url => {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`Cannot fetch ${url}: ${response.status}`);
    return new Uint8Array(await response.arrayBuffer());
  }));
  const seeded = new Uint8Array(await new Blob([initrd, await entropyArchive()]).arrayBuffer());
  module = {
    locateFile: name => new URL('./assets/' + name, import.meta.url).href,
    mainScriptUrlOrBlob: new URL('./assets/out.js', import.meta.url).href,
    pty: slave,
    printErr: text => { log = (log + text + '\n').slice(-16000); },
    onAbort: reason => fail(new Error(`QEMU aborted: ${reason}`)),
    preRun: [mod => {
      mod.FS.mkdir('/bridge');
      for (const name of ['request.json', 'response.json', 'result.json', 'transfers.bin', 'writeback.bin']) {
        mod.FS.writeFile('/bridge/' + name, new Uint8Array());
      }
      mod.FS.writeFile('/bridge/config.json', JSON.stringify({...message.config, mailboxToken}));
      mod.FS.writeFile('/bridge/app.lua', app);
      mod.FS.writeFile('/kernel', kernel);
      mod.FS.writeFile('/initramfs.gz', seeded);
    }],
    arguments: ['-nographic', '-M', 'pc', '-m', '256M', '-accel', 'tcg,tb-size=500',
      '-L', '/pack-rom/', '-nic', 'none', '-kernel', '/kernel', '-initrd', '/initramfs.gz',
      '-virtfs', 'local,path=/bridge,mount_tag=host,security_model=none',
      '-append', 'console=ttyS0 quiet rdinit=/init nupp.bridge=1 mem=192M iomem=relaxed'],
  };
  loadRoms(module);
  await initialize(module);
  const oldPoll = module.TTY.stream_ops.poll;
  module.TTY.stream_ops.poll = (stream, timeout) => !slave.readable ? (slave.writable ? 4 : 0) : oldPoll(stream, timeout);
}

self.addEventListener('message', event => {
  const message = event.data;
  if (message?.type === 'boot') { boot(message).catch(fail); return; }
  if (message?.type === 'clock-ready') { send('mailbox\n'); return; }
  if (message?.type !== 'response') return;
  try {
    if (!pending || pending.sequence !== message.sequence) throw new Error('Unexpected host response');
    const writes = [];
    const chunks = [];
    let offset = 0;
    for (const value of message.writes || []) {
      const lease = pending.leases.find(lease => lease.id === value.id);
      if (!lease?.writable || !(value.data instanceof ArrayBuffer) || value.data.byteLength !== lease.bytes) {
        throw new Error('Host attempted an invalid guest write');
      }
      if (writes.some(write => write.id === lease.id)) throw new Error('Duplicate host write');
      chunks.push(new Uint8Array(value.data));
      writes.push({id: lease.id, bytes: lease.bytes, offset});
      offset += lease.bytes;
    }
    const writeback = new Uint8Array(offset);
    chunks.forEach((chunk, i) => writeback.set(chunk, writes[i].offset));
    mailboxWrite(40 * 1024 * 1024, 3, MAX_TRANSFER, writeback);
    const released = message.released || [];
    if (released.some(id => !pending.leases.some(lease => lease.id === id))) throw new Error('Invalid lease release');
    mailboxWrite(32 * 1024 * 1024, 2, 8 * 1024 * 1024, encoder.encode(JSON.stringify({sequence: message.sequence, response: message.response, writes, released})));
    pending = undefined;
    send(String(message.sequence) + '\n');
  } catch (error) { fail(error); }
});
