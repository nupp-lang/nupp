import {spawn} from 'node:child_process';
import {mkdir, open, readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';

// Serve memory-64/web on 8099, memory-128/web on 8100, and
// memory-64-runtime/web on 8101 before running this bounded probe.
const root = path.resolve('build/v86-spike');
const output = path.join(root, 'memory-results');
await mkdir(output, {recursive: true});
const summary = [];
for (const test of [
  {profile: 'memory-64-runtime', port: 8101, mode: 'native'},
  {profile: 'memory-64-runtime', port: 8101, mode: 'game'},
  {profile: 'memory-64', port: 8099, mode: 'compiler', oom: true},
  {profile: 'memory-128', port: 8100, mode: 'compiler'},
]) {
  const name = test.profile + '-' + test.mode;
  const result = path.join(output, name + '.json');
  const log = await open(path.join(output, name + '.log'), 'w');
  let code;
  try {
    code = await new Promise((resolve, reject) => {
      const child = spawn(process.execPath, ['bench/qemu-wasm-spike/run-browser.mjs',
        `http://127.0.0.1:${test.port}/integration.html?mode=${test.mode}`, result], {
        stdio: ['ignore', log.fd, log.fd], env: {...process.env, SPIKE_TIMEOUT_MS: '60000'},
      });
      child.on('error', reject);
      child.on('exit', resolve);
    });
  } finally { await log.close(); }
  const data = JSON.parse(await readFile(result, 'utf8'));
  const expectedOom = test.oom && code === 1 && !data.ok &&
    /Out of memory: Killed process \d+ \(luajit\)/.test(data.error);
  if (!expectedOom && (test.oom || code !== 0 || !data.ok || data.browserErrors.length)) {
    throw new Error(name + ' did not produce the expected outcome; inspect its log');
  }
  const profile = JSON.parse(await readFile(path.join(root, test.profile, 'profile.json'), 'utf8'));
  summary.push({name, outcome: expectedOom ? 'guest-out-of-memory' : 'passed',
    wasmMemoryBytes: data[test.mode]?.metrics?.wasmMemoryBytes, profile});
  console.log(name + ': ' + summary.at(-1).outcome);
}
await writeFile(path.join(output, 'summary.json'), JSON.stringify(summary, null, 2) + '\n');
