import {readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {V86} from '../../build/v86-spike/startup/snapshot/assets/libv86.mjs';

const root = path.resolve('build/v86-spike/startup/snapshot');
const initrd = await readFile(path.join(root, 'snapshot-initramfs.gz'));
const emulator = new V86({
  wasm_path: path.join(root, 'assets/v86.wasm'),
  memory_size: 64 * 1024 * 1024, vga_memory_size: 1024 * 1024,
  bios: {url: path.join(root, 'assets/seabios.bin')},
  vga_bios: {url: path.join(root, 'assets/vgabios.bin')},
  bzimage: {url: path.join(root, 'assets/bzimage.bin')},
  initrd: {buffer: initrd.buffer.slice(initrd.byteOffset, initrd.byteOffset + initrd.byteLength)},
  cmdline: 'console=ttyS0,115200 quiet rootfstype=ramfs rdinit=/init mem=48M iomem=relaxed tsc=reliable random.trust_cpu=on nupp.bridge=1',
  autostart: true, disable_speaker: true, disable_mouse: true, disable_keyboard: true,
});
let partial = '', captured = false;
const timer = setTimeout(() => { console.error('Snapshot boot timed out'); emulator.destroy(); process.exit(1); }, 60000);
emulator.add_listener('serial0-output-byte', byte => {
  const text = String.fromCharCode(byte);
  if (text === '\r') return;
  if (text !== '\n') { partial += text; return; }
  const line = partial; partial = ''; console.log(line);
  if (line !== '@@NUPP_SNAPSHOT_READY@@' || captured) return;
  captured = true;
  (async () => {
    await emulator.stop();
    const state = Buffer.from(await emulator.save_state());
    await writeFile(path.join(root, 'guest-state.bin'), state);
    await writeFile(path.join(root, '../snapshot-bundled/guest-state.bin'), state);
    await writeFile(path.join(root, '../snapshot-build.json'), JSON.stringify({bytes: state.length,
      sha256: createHash('sha256').update(state).digest('hex'), capturedBeforeLuaJITAndHostData: true}, null, 2) + '\n');
    console.log('Saved', state.length, 'bytes');
    clearTimeout(timer); await emulator.destroy();
  })().catch(error => { console.error(error); process.exit(1); });
});
