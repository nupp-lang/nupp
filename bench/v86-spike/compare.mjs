import {spawn} from 'node:child_process';
import {mkdir, readFile, writeFile, open} from 'node:fs/promises';
import path from 'node:path';

const base = process.argv[2] || 'http://127.0.0.1:8099/';
const output = path.resolve(process.argv[3] || 'build/v86-spike/comparison');
await mkdir(output, {recursive: true});
const samples = [];
for (let pair = 0; pair < 3; pair++) {
  for (const backend of pair % 2 ? ['portable', 'v86'] : ['v86', 'portable']) {
    const url = new URL('integration.html?mode=game' + (backend === 'portable' ? '&portable' : ''), base);
    const result = path.join(output, `${backend}-${pair}.json`);
    const log = await open(path.join(output, `${backend}-${pair}.log`), 'w');
    const env = {...process.env, SPIKE_TIMEOUT_MS: '120000'};
    if (pair === 0 && backend === 'v86') env.SPIKE_SCREENSHOT = path.join(output, 'game.png');
    try {
      await new Promise((resolve, reject) => {
        const child = spawn(process.execPath, ['bench/qemu-wasm-spike/run-browser.mjs', url.href, result],
          {stdio: ['ignore', log.fd, log.fd], env});
        child.on('error', reject);
        child.on('exit', code => code === 0 ? resolve() : reject(new Error(`${backend} pair ${pair} failed; see ${backend}-${pair}.log`)));
      });
    } finally { await log.close(); }
    const value = JSON.parse(await readFile(result, 'utf8'));
    samples.push({backend, pair, firstFrameMs: value.firstFrameMs, ...value.frameTiming});
    console.log(backend, pair, value.frameTiming.averageFps.toFixed(2), 'fps');
  }
}
const median = values => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
const summary = {};
for (const backend of ['v86', 'portable']) {
  const selected = samples.filter(sample => sample.backend === backend);
  summary[backend] = Object.fromEntries(['firstFrameMs', 'averageFps', 'warmAverageFps', 'medianMs', 'p95Ms'].map(key => [key, median(selected.map(sample => sample[key]))]));
}
const result = {method: 'Three alternating paired fresh Chrome launches. Same Nupp source, 120 frames, 32768 updates per frame. Warm metric discards first 30 intervals. Exploratory, no confidence interval or machine isolation claim.', summary, samples};
await writeFile(path.join(output, 'summary.json'), JSON.stringify(result, null, 2) + '\n');
console.log(JSON.stringify(summary, null, 2));
