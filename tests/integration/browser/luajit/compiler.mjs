import {createCompiler} from './host.mjs';
const output = document.querySelector('#result');
const terminal = document.querySelector('#terminal');
let compiler;
function equivalent(actual, expected, path = 'response') {
  if (typeof actual !== typeof expected || actual === null || expected === null) {
    if (actual !== expected) throw new Error(`${path}: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  } else if (typeof expected === 'object') {
    if (Array.isArray(actual) !== Array.isArray(expected)) throw new Error(`${path}: array/object mismatch`);
    if (JSON.stringify(Object.keys(actual).sort()) !== JSON.stringify(Object.keys(expected).sort()))
      throw new Error(`${path}: different fields`);
    for (const key of Object.keys(expected)) equivalent(actual[key], expected[key], `${path}.${key}`);
  } else if (actual !== expected) throw new Error(`${path}: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
}
try {
  const app = new Uint8Array(await (await fetch('./compiler.ljbc')).arrayBuffer());
  const requests = await (await fetch('./compiler-requests.json')).json();
  const expected = await (await fetch('./compiler-expected.json')).json();
  const started = performance.now();
  compiler = await createCompiler({manifestUrl: './guest-manifest.json', app, deadlineMs: 180000,
    onProgress: message => { if (message.log) terminal.textContent = message.log; }});
  const startupMs = performance.now() - started;
  const samples = [];
  for (let round = 0; round < 3; round++) {
    for (const [index, request] of requests.entries()) {
      const {expect, ...compilerRequest} = request;
      const start = performance.now();
      const response = await compiler.request(compilerRequest);
      samples.push({round, index, kind: request.kind, durationMs: performance.now() - start});
      equivalent(response, expected[index], `round ${round} request ${index}`);
    }
  }
  output.textContent = JSON.stringify({ok: true, startupMs, requests: samples.length, samples, compilerBytes: app.length});
  output.dataset.status = 'passed';
} catch (error) {
  output.textContent = JSON.stringify({ok: false, error: String(error.stack || error)});
  output.dataset.status = 'failed';
} finally { compiler?.close(); }
