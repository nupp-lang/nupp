import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';

const root = 'build/v86-spike/startup';
const output = 'bench/v86-spike/results/startup';
fs.mkdirSync(output, {recursive: true});
const read = name => JSON.parse(fs.readFileSync(name, 'utf8'));
const save = (name, value) => fs.writeFileSync(path.join(output, name), JSON.stringify(value, null, 2) + '\n');
const digest = name => {
  const bytes = fs.readFileSync(name);
  return {bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex')};
};
const stats = values => {
  const sorted = values.toSorted((a, b) => a - b);
  return {median: sorted[Math.floor(sorted.length / 2)], min: sorted[0], max: sorted.at(-1), n: sorted.length};
};
const rows = [];
for (const label of process.argv.slice(2)) {
  const directory = path.join(root, label);
  const samples = read(path.join(directory, 'summary.json'));
  for (const sample of samples) {
    const result = read(path.join(directory, `${sample.pair}-${sample.variant}-${sample.visit}.json`));
    if (!result.ok || result.browserErrors.length || !result.isolated) throw new Error('Invalid sample');
    if (result.game.value.frames !== 120 || result.game.value.updates !== 3932160 ||
        result.game.value.checksum !== 1966080 || !result.game.value.jit ||
        !result.interaction.clicks || !result.interaction.keyEvents ||
        result.interaction.audioState !== 'running' || result.interaction.offlineAudioPeak < 0.5 ||
        result.interaction.canvasPixel[1] < 150) throw new Error('Game assertion failed');
    if (sample.visit === 'cached' && sample.delivery.payloadBytes !== 0) throw new Error('Unexpected cache miss');
    sample.validation = {game: result.game.value, interaction: result.interaction,
      isolated: result.isolated, browserErrors: result.browserErrors};
  }
  save(label + '.json', samples);
  for (const variant of [...new Set(samples.map(sample => sample.variant))]) {
    for (const visit of ['cold', 'cached']) {
      const selected = samples.filter(sample => sample.variant === variant && sample.visit === visit);
      if (!selected.length) continue;
      const fields = Object.keys(selected[0].startup);
      rows.push({label, variant, visit, firstFrameMs: stats(selected.map(sample => sample.firstFrameMs)),
        navigationToFirstFrameMs: stats(selected.map(sample => sample.navigationToFirstFrameMs)),
        bodyBytes: stats(selected.map(sample => sample.delivery.payloadBytes)),
        warmFps: stats(selected.map(sample => sample.warmFps)),
        wasmMemoryBytes: stats(selected.map(sample => sample.wasmMemoryBytes)),
        startup: Object.fromEntries(fields.map(field => [field, stats(selected.map(sample => sample.startup[field]))]))});
    }
  }
}
save('summary.json', rows);
for (const name of ['snapshot-build', 'snapshot-check', 'snapshot-lifecycle']) {
  save(name + '.json', read(path.join(root, name + '.json')));
}
const sourceFiles = ['build-snapshot.mjs', 'check-startup.mjs', 'prepare-startup.py', 'startup-boot.mjs',
  'startup-receive.c', 'delivery-server.mjs', 'probe-delivery.mjs', 'record-startup.mjs'].map(name => 'bench/v86-spike/' + name);
sourceFiles.push('bench/qemu-wasm-spike/run-browser.mjs');
const artifacts = {};
for (const variant of ['serial', 'parallel', 'parallel-raw', 'snapshot', 'snapshot-bundled']) {
  for (const name of ['vm-worker.mjs', 'guest-runtime.mjs', 'integration.mjs', 'app.ljbc', 'initramfs.gz',
    'initramfs.cpio', 'guest-state.bin', 'assets/libv86.mjs', 'assets/v86.wasm', 'assets/bzimage.bin']) {
    const filename = path.join(root, variant, name);
    if (fs.existsSync(filename)) artifacts[variant + '/' + name] = digest(filename);
  }
}
save('provenance.json', {recordedAt: new Date().toISOString(),
  baseRevision: execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
  platform: process.platform, arch: process.arch, osRelease: os.release(), cpu: os.cpus()[0].model,
  node: process.version, chrome: read(path.join(root, 'snapshot-check.json')).userAgent,
  sourceFiles: Object.fromEntries(sourceFiles.map(name => [name, digest(name)])), artifacts,
  method: 'Sequential fresh Chrome processes; each cached visit reuses only its paired disk-cache profile. Alternating variant order. Brotli quality 9 when smaller, except quality11-10mbps uses 11. Link model shares a 1,250,000 byte/s body budget and delays each response 80 ms. No TCP simulation. Body bytes exclude headers.',
  timing: 'firstFrameMs starts when the page calls startGuest, after page module loading; navigationToFirstFrameMs includes that earlier loading. Startup marks share performance.timeOrigin. Controlled runs attach CDP before navigation; initial runs attach while the page loads.',
  limitations: 'Exploratory samples on one desktop Chromium version, not a confidence interval, mobile/browser survey, production integration, or playground compiler snapshot.'});
for (const row of rows) console.log(row.label, row.variant, row.visit,
  row.firstFrameMs.median.toFixed(1), row.navigationToFirstFrameMs.median.toFixed(1), row.bodyBytes.median);
