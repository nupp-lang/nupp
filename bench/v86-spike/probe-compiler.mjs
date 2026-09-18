import {spawn} from 'node:child_process';
import {mkdir, open, readFile, writeFile} from 'node:fs/promises';
import path from 'node:path';

const output = path.resolve('build/v86-spike/performance/compiler-pairs');
await mkdir(output, {recursive: true});
const summary = [];
const cases = JSON.parse(await readFile('build/v86-spike/performance/web/compiler-cases.json', 'utf8'));
const canonical = value => JSON.stringify(value, function(key, entry) {
  if (key === 'diagnostics' && entry && !Array.isArray(entry) && !Object.keys(entry).length) return [];
  return entry && typeof entry === 'object' && !Array.isArray(entry)
    ? Object.fromEntries(Object.keys(entry).sort().map(key => [key, entry[key]])) : entry;
});
const variants = process.argv.slice(2);
const selected = variants.length ? variants : ['v86-jit', 'v86-interpreter', 'lua51'];
for (let pair = 0; pair < Number(process.env.COMPILER_PAIRS || 2); pair++) {
  for (const backend of pair % 2 ? [...selected].reverse() : selected) {
    const name = `${pair}-${backend}`;
    const url = backend === 'lua51' ? 'http://127.0.0.1:8102/compiler-portable.html'
      : 'http://127.0.0.1:8102/integration.html?mode=compiler&native-bit&reuse&rounds=3&slim' + (backend === 'v86-interpreter' ? '&no-jit' : '');
    const log = await open(path.join(output, name + '.log'), 'w');
    let code;
    try {
      code = await new Promise((resolve, reject) => {
        const child = spawn(process.execPath, ['bench/qemu-wasm-spike/run-browser.mjs', url, path.join(output, name + '.json')],
          {stdio: ['ignore', log.fd, log.fd], env: {...process.env, SPIKE_TIMEOUT_MS: '180000'}});
        child.on('error', reject); child.on('exit', resolve);
      });
    } finally { await log.close(); }
    if (code !== 0) throw new Error(name + ' failed; inspect its log');
    const result = JSON.parse(await readFile(path.join(output, name + '.json'), 'utf8'));
    if (backend !== 'lua51') {
      const value = result.compiler.value;
      if (!value.nativeBit || !value.hashKnownAnswers || value.jitEnabled !== (backend === 'v86-jit')) throw new Error(name + ': configuration/oracle mismatch');
      const requests = value.requests.filter(entry => entry.input);
      if (requests.length !== cases.length * 3) throw new Error(name + ': missing requests');
      for (const [index, entry] of requests.entries()) {
        const expected = cases[index % cases.length];
        if (canonical(entry.input) !== canonical(expected.input) || canonical(entry.response) !== canonical(expected.response)) throw new Error(name + ': response differs: ' + entry.name);
      }
      result.responsesMatchNativeAndLua51 = true;
    }
    summary.push({pair, backend, result});
    await writeFile(path.join(output, 'summary.json'), JSON.stringify(summary, null, 2) + '\n');
    console.log(name, backend === 'lua51' ? result.rounds.map(round => round.reduce((sum, entry) => sum + entry.ms, 0)) : result.compiler.value.rounds);
  }
}
