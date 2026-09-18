import {spawn} from 'node:child_process';
import {mkdir, mkdtemp, open, readFile, rm, writeFile} from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';

const base = process.argv[2] || 'http://127.0.0.1:8103';
const label = process.argv[3] || 'local';
const output = path.resolve(process.env.DELIVERY_OUTPUT || 'build/v86-spike/performance/delivery-' + label);
const variants = (process.env.DELIVERY_VARIANTS || 'raw,compressed,slim').split(',');
await mkdir(output, {recursive: true});
const samples = [];
for (let pair = 0; pair < Number(process.env.DELIVERY_PAIRS || 3); pair++) {
  for (const variant of pair % 2 ? [...variants].reverse() : variants) {
    const profile = await mkdtemp(path.join(os.tmpdir(), 'nupp-delivery-'));
    try {
      for (const visit of ['cold', 'cached']) {
        const name = `${pair}-${variant}-${visit}`;
        await fetch(base + '/_stats', {method: 'POST'});
        const log = await open(path.join(output, name + '.log'), 'w');
        let code;
        try {
          code = await new Promise((resolve, reject) => {
            const child = spawn(process.execPath, ['bench/qemu-wasm-spike/run-browser.mjs',
              `${base}/${variant}/integration.html?mode=game`, path.join(output, name + '.json')],
              {stdio: ['ignore', log.fd, log.fd], env: {...process.env, SPIKE_PROFILE_DIR: profile, SPIKE_TIMEOUT_MS: '90000'}});
            child.on('error', reject); child.on('exit', resolve);
          });
        } finally { await log.close(); }
        if (code !== 0) throw new Error(name + ' failed; inspect its log');
        const result = JSON.parse(await readFile(path.join(output, name + '.json'), 'utf8'));
        const delivery = await (await fetch(base + '/_stats')).json();
        samples.push({pair, variant, visit, firstFrameMs: result.firstFrameMs,
          navigationToFirstFrameMs: result.navigationToFirstFrameMs,
          bootMs: result.game.metrics.bootMs, wasmMemoryBytes: result.game.metrics.wasmMemoryBytes,
          startup: result.game.metrics.startup,
          warmFps: result.frameTiming.warmAverageFps, delivery});
        await writeFile(path.join(output, 'summary.json'), JSON.stringify(samples, null, 2) + '\n');
        console.log(name, result.firstFrameMs.toFixed(1), delivery.payloadBytes);
      }
    } finally { await rm(profile, {recursive: true, force: true}); }
  }
}
