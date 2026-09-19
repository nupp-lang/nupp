import {chromium, firefox, webkit} from 'playwright';
import {readFileSync, writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import os from 'node:os';

const [url, output] = process.argv.slice(2);
if (!url || !output) throw new Error('usage: imported-performance.mjs PLAYGROUND_URL RESULT.json');
const fixture = new URL('../../../bench/luajit-browser/imported-scoreboard.nupp', import.meta.url);
const source = readFileSync(fixture, 'utf8');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const repetitions = Number(process.env.NUPP_BENCH_REPETITIONS || 3);
const samples = Number(process.env.NUPP_BENCH_SAMPLES || 30);
const fetchAsset = async name => {
  const response = await fetch(new URL(name, url));
  if (!response.ok) throw new Error(`Asset ${name}: HTTP ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  return {name, bytes: bytes.length, sha256: hash(bytes)};
};
const manifestResponse = await fetch(new URL('nupp-playground-assets.json', url));
if (!manifestResponse.ok) throw new Error('Missing production asset manifest');
const manifest = await manifestResponse.json();
const guestResponse = await fetch(new URL(manifest.luajit.guestManifest, url));
const guestManifest = await guestResponse.json();
const metadata = {
  scope: 'Production retained compiler workers: changing application edits with six bundled-library imports. Browser memoryOnly sessions accept one source and lazily check bundled modules; they cannot load arbitrary project files. This is not a multi-file incremental-project benchmark, UI responsiveness budget, physical mobile test, or network-delivery measurement.',
  timing: 'Page performance.now immediately before worker.postMessage until the matching response: includes structured clone, queue, raw-source guest bridge, compiler execution, and response. Worker boot excluded from edit timing. Fresh first check includes lazy imported-module checking; warm check and compile reuse the same worker/environment. Hover follows each changed check and is timed separately.',
  hostConditions: process.env.NUPP_BENCH_HOST_CONDITIONS || 'Not independently verified idle; interleaved backend order reduces but does not remove shared-host variation.',
  commit: execFileSync('git', ['rev-parse', 'HEAD'], {encoding: 'utf8'}).trim(),
  host: {platform: os.platform(), arch: os.arch(), cpu: os.cpus()[0].model, memoryBytes: os.totalmem()},
  repetitions, samples, warmups: 3,
  fixture: {path: 'bench/luajit-browser/imported-scoreboard.nupp', sha256: hash(source), bytes: Buffer.byteLength(source), source},
  imports: [...source.matchAll(/require\("([^"]+)"\)/g)].map(match => match[1]),
  edits: 'Replace round integer 5 and both scoreboard-edit-5 string literals with trial+5 on every request. Each compile must contain its current changed string. Every check/compile must return zero errors; every hover must identify wire as string. After timing, each imported API must reject a wrong argument with NUPP2006.',
  manifest, guestManifest,
  assets: await Promise.all(['worker.js', 'legacy-worker.js', manifest.compiler, manifest.hostModule, manifest.hostWasm, manifest.luajit.compiler].map(fetchAsset)),
  results: [],
};
for (const engine of (process.env.NUPP_TEST_BROWSERS || 'chromium,firefox,webkit').split(',')) {
  for (let round = 0; round < repetitions; round++) {
    const browser = await {chromium, firefox, webkit}[engine].launch({headless: true, ...(engine === 'chromium' ? {channel: 'chrome'} : {})});
    try {
      const page = await browser.newPage();
      // Keep this real HTTP navigation (a plain 404 page also works). Playwright
      // request interception breaks the emulator's blob workers in WebKit.
      await page.goto(new URL('performance-empty.html', url).href);
      for (const backend of round % 2 ? ['lua51', 'luajit'] : ['luajit', 'lua51']) {
        console.log(engine, round, backend);
        const result = await page.evaluate(async ({backend, source, samples}) => {
          const started = performance.now();
          const worker = new Worker(backend === 'luajit' ? './worker.js' : './legacy-worker.js', {type: 'module'});
          let id = 0;
          let phase = 'boot';
          const bounded = action => new Promise((resolve, reject) => {
            const timer = setTimeout(() => reject(new Error('Compiler request timeout')), 120000);
            action(value => {clearTimeout(timer); resolve(value);}, error => {clearTimeout(timer); reject(error);});
          });
          const options = {dialect: backend, strict: true, optimize: true};
          try {
            await bounded((resolve, reject) => {
              worker.onmessage = ({data}) => {
                if (data.type === 'ready') resolve();
                if (data.type === 'boot-error') reject(new Error(data.message));
              };
              worker.onerror = event => reject(new Error(event.message));
            });
            const startupMs = performance.now() - started;
            const request = body => bounded((resolve, reject) => {
              const current = ++id;
              worker.onmessage = ({data}) => {
                if (data.id !== current) return;
                if (data.ok) resolve(data);
                else reject(new Error(data.error));
              };
              worker.postMessage({id: current, filename: 'imported-scoreboard.nupp', options, ...body});
            });
            const summarize = (kind, values, firstRequestMs) => {
              const ordered = [...values].sort((a, b) => a - b);
              return {kind, firstRequestMs, samples: values, p50Ms: ordered[Math.ceil(values.length * .5) - 1], p95Ms: ordered[Math.ceil(values.length * .95) - 1]};
            };
            const summary = [];
            let hoverResponse;
            for (const kind of ['check', 'compile']) {
              const values = [], hovers = [];
              let firstRequestMs;
              for (let trial = -3; trial < samples; trial++) {
                phase = `${kind} trial ${trial}`;
                const revision = trial + 5;
                const changed = source.replace('round: integer = 5', `round: integer = ${revision}`).replaceAll('scoreboard-edit-5', `scoreboard-edit-${revision}`);
                const begin = performance.now();
                const response = await request({kind, source: changed});
                const elapsed = performance.now() - begin;
                if (response.diagnostics?.some(item => item.severity === 'error')) throw new Error(JSON.stringify(response));
                if (kind === 'compile' && (!response.code || !response.code.includes(`scoreboard-edit-${revision}`))) throw new Error('Missing current edited literal in compiled output');
                if (trial === -3) firstRequestMs = elapsed;
                if (trial >= 0) values.push(elapsed);
                if (kind === 'check') {
                  phase = `hover trial ${trial}`;
                  const hoverStarted = performance.now();
                  hoverResponse = await request({kind: 'hover', offset: changed.lastIndexOf('wire') + 1});
                  const hoverMs = performance.now() - hoverStarted;
                  if (!hoverResponse.found || hoverResponse.name !== 'wire' || hoverResponse.signature !== 'wire: string') throw new Error(JSON.stringify(hoverResponse));
                  if (trial >= 0) hovers.push(hoverMs);
                }
              }
              summary.push(summarize(kind + '-edit', values, firstRequestMs));
              if (kind === 'check') summary.push(summarize('hover', hovers));
            }
            const invalidCalls = ['json.decode(false)', 'hex.encode(false)', 'text.newBuffer(false)', 'utf8.truncate(false, 24)', 'path.newPath(false)', 'uri.newURI(false)'];
            const importedTypeChecks = [];
            for (const call of invalidCalls) {
              phase = `imported argument validation: ${call}`;
              const invalid = source.replace('return report,', `${call}\nreturn report,`);
              const response = await request({kind: 'check', source: invalid});
              const diagnostics = response.diagnostics.filter(item => item.severity === 'error');
              if (!diagnostics.some(item => item.code === 'NUPP2006')) throw new Error(`Imported API was not checked: ${call}: ${JSON.stringify(response)}`);
              importedTypeChecks.push({call, diagnostics});
            }
            return {startupMs, summary, hoverResponse: {found: hoverResponse.found, name: hoverResponse.name, signature: hoverResponse.signature}, importedTypeChecks};
          } catch (error) {
            return {failed: true, failure: {phase, message: String(error.message || error), stack: String(error.stack || ''), elapsedMs: performance.now() - started}};
          } finally {worker.terminate();}
        }, {backend, source, samples});
        metadata.results.push({engine, round, version: browser.version(), backend, ...result});
        writeFileSync(output, JSON.stringify(metadata, null, 2) + '\n');
      }
    } finally {await browser.close();}
  }
}
for (const engine of new Set(metadata.results.map(result => result.engine))) {
  const successful = metadata.results.filter(result => result.engine === engine && !result.failed);
  const baseline = successful[0];
  const canonical = value => Array.isArray(value) ? value.map(canonical)
    : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
  const oracle = result => JSON.stringify(canonical({hover: result.hoverResponse, invalid: result.importedTypeChecks}));
  for (const result of successful) {
    if (oracle(result) !== oracle(baseline)) throw new Error(`Compiler response mismatch: ${engine}, round ${result.round}, ${result.backend}`);
  }
}
metadata.responseEquivalence = 'Successful sessions have identical hover types and complete imported-argument diagnostics within each engine; all valid changed checks/compiles passed, and compiled output retained the current source literal.';
metadata.failedSessions = metadata.results.filter(result => result.failed).length;
writeFileSync(output, JSON.stringify(metadata, null, 2) + '\n');
if (metadata.failedSessions) process.exitCode = 1;
