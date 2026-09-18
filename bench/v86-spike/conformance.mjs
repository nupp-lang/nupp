import {spawn} from 'node:child_process';
import {mkdir, open, readFile, writeFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import path from 'node:path';

const base = process.argv[2] || 'http://127.0.0.1:8099/';
const output = path.resolve(process.argv[3] || 'build/v86-spike/conformance');
await mkdir(output, {recursive: true});
// Run the existing negative transfer checks against the staged v86 host adapter.
const transport = (await readFile('bench/qemu-wasm-spike/transport-tests.mjs', 'utf8'))
  .replace('../../build/qemu-wasm-spike/web/guest-runtime.mjs', pathToFileURL(path.resolve('build/v86-spike/web/guest-runtime.mjs')).href)
  .replace('../../runtime/wasm/app-runtime.mjs', pathToFileURL(path.resolve('runtime/wasm/app-runtime.mjs')).href);
await import('data:text/javascript;base64,' + Buffer.from(transport).toString('base64'));
const summary = {transport: true, modes: {}};
for (const mode of ['features', 'native', 'services', 'gpu', 'workers', 'deadline', 'lifecycle', 'game']) {
  const log = await open(path.join(output, mode + '.log'), 'w');
  const result = path.join(output, mode + '.json');
  try {
    await new Promise((resolve, reject) => {
      const child = spawn(process.execPath, ['bench/qemu-wasm-spike/run-browser.mjs',
        new URL('integration.html?mode=' + mode, base).href, result], {
        stdio: ['ignore', log.fd, log.fd],
        env: {...process.env, SPIKE_GPU: mode === 'gpu' ? '1' : '0', SPIKE_TIMEOUT_MS: '120000',
          ...(mode === 'game' ? {SPIKE_SCREENSHOT: path.join(output, 'game.png')} : {})},
      });
      child.on('error', reject);
      child.on('exit', code => code === 0 ? resolve() : reject(new Error(mode + ' failed; see ' + mode + '.log')));
    });
  } finally { await log.close(); }
  const data = JSON.parse(await readFile(result, 'utf8'));
  if (!data.ok || data.browserErrors.length) throw new Error(mode + ' did not pass');
  summary.modes[mode] = true;
  console.log(mode + ' passed');
}
await writeFile(path.join(output, 'summary.json'), JSON.stringify(summary, null, 2) + '\n');
