import {createCompilerHost} from './wasm-runtime.js';
const canonical = value => JSON.stringify(value, function(key, entry) {
  return entry && typeof entry === 'object' && !Array.isArray(entry)
    ? Object.fromEntries(Object.keys(entry).sort().map(key => [key, entry[key]])) : entry;
});
try {
  const cases = await (await fetch('./compiler-cases.json')).json();
  const digest = await (await fetch('./compiler-digest.txt')).text();
  const host = await createCompilerHost({
    moduleUrl: new URL('./nupp-playground.mjs', import.meta.url).href,
    wasmUrl: new URL('./nupp-playground.wasm', import.meta.url).href,
    compilerUrl: './nupp-compiler.lua', expectedDigest: digest.trim(),
  });
  const report = {ok: true, backend: 'existing-lua51-wasm', boot: host.timings, rounds: []};
  for (let round = 0; round < 3; round++) {
    const requests = [];
    for (const entry of cases) {
      postMessage({progress: `${round}: ${entry.name}`});
      const started = performance.now();
      const response = host.request(entry.input);
      const ms = performance.now() - started;
      if (canonical(response) !== canonical(entry.response)) throw new Error(`Response differs: ${entry.name}\n${canonical(response)}\n${canonical(entry.response)}`);
      requests.push({name: entry.name, ms});
    }
    report.rounds.push(requests);
  }
  postMessage({result: report});
} catch (error) { postMessage({result: {ok: false, error: String(error.stack || error)}}); }
