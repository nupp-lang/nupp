// Fast diagnostic runner; retained browser/CDP runs provide the browser proof.
import {readFile, writeFile} from 'node:fs/promises';
import {gzipSync} from 'node:zlib';
import {randomBytes} from 'node:crypto';
import path from 'node:path';
import {V86} from '../../build/v86-spike/web/assets/libv86.mjs';

const base = path.resolve('build/v86-spike/web');
const started = performance.now();
function cpio(name, data) {
  const filename = Buffer.from(name + '\0');
  const header = Buffer.from('070701' + [1, 0o100400, 0, 0, 1, 0, data.length, 0, 0, 0, 0, filename.length, 0].map(n => n.toString(16).padStart(8, '0')).join(''));
  return Buffer.concat([header, filename, Buffer.alloc((4 - (110 + filename.length) % 4) % 4), data, Buffer.alloc((4 - data.length % 4) % 4)]);
}
const seed = gzipSync(Buffer.concat([cpio('nupp/entropy.bin', randomBytes(32)), cpio('TRAILER!!!', Buffer.alloc(0))]));
const initrd = Buffer.concat([await readFile(path.join(base, 'initramfs.gz')), seed]);
const emulator = new V86({
  wasm_path: path.join(base, 'assets/v86.wasm'),
  memory_size: 256 * 1024 * 1024, vga_memory_size: 1024 * 1024,
  bios: {url: path.join(base, 'assets/seabios.bin')},
  vga_bios: {url: path.join(base, 'assets/vgabios.bin')},
  bzimage: {url: path.join(base, 'assets/bzimage.bin')},
  initrd: {buffer: initrd.buffer.slice(initrd.byteOffset, initrd.byteOffset + initrd.byteLength)},
  cmdline: 'console=ttyS0,115200 earlyprintk=serial,ttyS0,115200 rdinit=/init random.trust_cpu=on',
  autostart: true, disable_speaker: true, disable_mouse: true, disable_keyboard: true,
});
let output = '', partial = '';
let readyMs;
const diagnostic = setInterval(() => {
  console.error('V86 state', {running: emulator.is_running(), instructions: emulator.get_instruction_counter(),
    eip: emulator.v86?.cpu?.instruction_pointer?.[0], outputBytes: output.length});
}, 10000);
emulator.add_listener('emulator-loaded', () => console.error('V86 loaded'));
emulator.add_listener('emulator-started', () => console.error('V86 started'));
emulator.add_listener('download-error', value => console.error('V86 download error', value));
let screen = '';
emulator.add_listener('screen-put-char', data => { screen += String.fromCharCode(data[2]); });
const timeout = setTimeout(() => { console.error('Timed out', output.slice(-4000), screen.slice(-4000)); emulator.destroy(); process.exit(1); }, 90000);
emulator.add_listener('serial0-output-byte', byte => {
  const char = String.fromCharCode(byte); output += char; partial += char;
  if (char !== '\n') return;
  process.stdout.write(partial); partial = '';
  if (output.includes('@@NUPP_QEMU_READY@@') && readyMs === undefined) readyMs = performance.now() - started;
  const exit = output.match(/@@NUPP_QEMU_EXIT@@ (\d+)/);
  if (exit) {
    clearTimeout(timeout);
    clearInterval(diagnostic);
    const metrics = {exitCode: Number(exit[1]), readyMs, totalMs: performance.now() - started,
      wasmMemoryBytes: emulator.v86.cpu.wasm_memory.buffer.byteLength};
    console.log(JSON.stringify(metrics));
    writeFile('build/v86-spike/node-result.json', JSON.stringify({...metrics, output}, null, 2) + '\n')
      .then(() => emulator.destroy()).then(() => process.exit(metrics.exitCode));
  }
});
