import {chromium, firefox, webkit} from '../../editors/playground/node_modules/playwright/index.mjs';
import {createServer} from 'node:http';
import {createReadStream, readFileSync, statSync, writeFileSync, mkdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';

const root = path.resolve(fileURLToPath(new URL('../../', import.meta.url)));
const [control, candidate, manifestPath, output] = process.argv.slice(2).map(value => path.resolve(value));
if (!output) throw new Error('usage: compiler-pair.mjs CONTROL.ljbc CANDIDATE.ljbc GUEST_MANIFEST RESULT.json');
const fixturePath = path.join(root, 'bench/luajit-browser/imported-scoreboard.nupp');
const source = readFileSync(fixturePath, 'utf8');
const hash = value => createHash('sha256').update(value).digest('hex');
const asset = filename => {
  const bytes = readFileSync(filename);
  return {path: path.relative(root, filename), bytes: bytes.length, sha256: hash(bytes)};
};
const relative = filename => {
  const name = path.relative(root, filename);
  if (name.startsWith('../') || path.isAbsolute(name)) throw new Error('Benchmark inputs must be inside the checkout');
  return name.split(path.sep).map(encodeURIComponent).join('/');
};
const repetitions = Number(process.env.NUPP_BENCH_REPETITIONS || 3);
const samples = Number(process.env.NUPP_BENCH_SAMPLES || 30);
const deadlineMs = 120000;
const metadata = {
  scope: 'Isolated compiler bytecode A/B in the production raw-source retained guest protocol, compiler JIT disabled. Identical verified guest and workload; only the supplied compiler artifacts vary. This is not a production UI, network-delivery, arbitrary multi-file project, or physical-device benchmark.',
  timing: 'Browser performance.now round trips. Compiler bytecode fetch finishes before startup timing. Startup is createGuest to compiler-ready. First check includes lazy bundled-import closure; warm check/compile retain the environment. Three changing warmups precede measured edits. Hover follows every changed check.',
  hostConditions: process.env.NUPP_BENCH_HOST_CONDITIONS || 'Shared host; concurrent work may affect absolute timings. Alternating order reduces but does not remove variation.',
  commit: execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim(),
  host: {platform: os.platform(), arch: os.arch(), cpu: os.cpus()[0].model, memoryBytes: os.totalmem()},
  repetitions, samples, warmups: 3, deadlineMs,
  fixture: {...asset(fixturePath), source},
  compiler: {control: asset(control), candidate: asset(candidate)},
  harness: asset(fileURLToPath(import.meta.url)),
  hostModule: asset(path.join(root, 'runtime/luajit/host.mjs')),
  guestManifest: {...asset(manifestPath), manifest: JSON.parse(readFileSync(manifestPath, 'utf8'))},
  edits: 'Change round and both scoreboard-edit literals on every request; verify current compiled literal, matching generated-code hashes, wire:string hover, and NUPP2006 rejection for all six imported APIs.',
  results: [],
};
mkdirSync(path.dirname(output), {recursive: true});
const record = () => writeFileSync(output, JSON.stringify(metadata, null, 2) + '\n');
const types = {'.mjs': 'text/javascript', '.js': 'text/javascript', '.json': 'application/json', '.wasm': 'application/wasm'};
const server = createServer((request, response) => {
  response.setHeader('Cache-Control', 'no-store');
  const url = new URL(request.url, 'http://localhost');
  if (url.pathname === '/') {
    response.setHeader('Content-Type', 'text/html');
    response.end('<!doctype html><title>Compiler bytecode comparison</title>');
    return;
  }
  try {
    const filename = path.resolve(root, '.' + decodeURIComponent(url.pathname));
    if (!filename.startsWith(root + path.sep) || !statSync(filename).isFile()) throw new Error('Not a file');
    response.setHeader('Content-Type', types[path.extname(filename)] || 'application/octet-stream');
    response.setHeader('Content-Length', statSync(filename).size);
    createReadStream(filename).on('error', () => response.destroy()).pipe(response);
  } catch {
    response.writeHead(404);
    response.end('Not found');
  }
});
await new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen(0, '127.0.0.1', resolve);
});
const base = `http://127.0.0.1:${server.address().port}/`;
try {
  for (const engine of (process.env.NUPP_TEST_BROWSERS || 'chromium').split(',')) {
    for (let round = 0; round < repetitions; round++) {
      const browser = await {chromium, firefox, webkit}[engine].launch({headless: true, ...(engine === 'chromium' ? {channel: 'chrome'} : {})});
      try {
        for (const variant of round % 2 ? ['candidate', 'control'] : ['control', 'candidate']) {
          const context = await browser.newContext();
          const page = await context.newPage();
          const errors = [];
          page.on('pageerror', error => errors.push(String(error)));
          await page.goto(base);
          console.log(`${engine} round ${round} ${variant}: starting`);
          const hostLoadBefore = os.loadavg();
          try {
            const result = await page.evaluate(async ({appUrl, manifestUrl, hostUrl, source, samples, deadlineMs}) => {
              const {createGuest} = await import(hostUrl);
              const fetched = await fetch(appUrl);
              if (!fetched.ok) throw new Error(`Compiler fetch failed: ${fetched.status}`);
              const app = new Uint8Array(await fetched.arrayBuffer());
              const started = performance.now();
              let phase = 'boot';
              const progress = [];
              const guest = createGuest({manifestUrl, app, profile: 'compiler', config: {mode: 'compiler', jit: false}, deadlineMs,
                onProgress: message => {if (message.type !== 'log') progress.push(message);}});
              const canonical = value => Array.isArray(value) ? value.map(canonical)
                : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
              const digest = async text => [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)))].map(byte => byte.toString(16).padStart(2, '0')).join('');
              const request = async body => {
                const {source, ...header} = body;
                guest.respond({...header, filename: 'imported-scoreboard.nupp', options: {dialect: 'luajit', strict: true, optimize: true},
                  ...(source === undefined ? {} : {payloadField: 'source'})}, new TextEncoder().encode(source || ''));
                const answer = await guest.receive();
                if (answer.type !== 'compiler' || !answer.result.ok) throw new Error(JSON.stringify(answer));
                return answer.result.response;
              };
              const summarize = (kind, values, firstRequestMs) => {
                const ordered = [...values].sort((a, b) => a - b);
                return {kind, firstRequestMs, samples: values, p50Ms: ordered[Math.ceil(values.length * .5) - 1], p95Ms: ordered[Math.ceil(values.length * .95) - 1]};
              };
              try {
                const ready = await guest.receive();
                if (ready.type !== 'compiler' || !ready.result.ready) throw new Error(JSON.stringify(ready));
                const startupMs = performance.now() - started;
                const summary = [], compileDigests = [], diagnosticDigests = [];
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
                    diagnosticDigests.push(await digest(JSON.stringify(canonical(response.diagnostics))));
                    if (kind === 'compile') {
                      if (!response.code?.includes(`scoreboard-edit-${revision}`)) throw new Error('Current edited literal absent');
                      compileDigests.push(await digest(response.code));
                    }
                    if (trial === -3) firstRequestMs = elapsed;
                    if (trial >= 0) values.push(elapsed);
                    if (kind === 'check') {
                      phase = `hover trial ${trial}`;
                      const beginHover = performance.now();
                      hoverResponse = await request({kind: 'hover', offset: changed.lastIndexOf('wire') + 1});
                      const hoverMs = performance.now() - beginHover;
                      if (!hoverResponse.found || hoverResponse.name !== 'wire' || hoverResponse.signature !== 'wire: string') throw new Error(JSON.stringify(hoverResponse));
                      if (trial >= 0) hovers.push(hoverMs);
                    }
                  }
                  summary.push(summarize(kind + '-edit', values, firstRequestMs));
                  if (kind === 'check') summary.push(summarize('hover', hovers));
                }
                const importedTypeChecks = [];
                for (const call of ['json.decode(false)', 'hex.encode(false)', 'text.newBuffer(false)', 'utf8.truncate(false, 24)', 'path.newPath(false)', 'uri.newURI(false)']) {
                  phase = `invalid imported API: ${call}`;
                  const response = await request({kind: 'check', source: source.replace('return report,', `${call}\nreturn report,`)});
                  const diagnostics = response.diagnostics.filter(item => item.severity === 'error');
                  if (!diagnostics.some(item => item.code === 'NUPP2006')) throw new Error(JSON.stringify({call, response}));
                  importedTypeChecks.push({call, diagnostics});
                }
                return {startupMs, summary, compileDigests, diagnosticDigests, hoverResponse, importedTypeChecks, progress};
              } catch (error) {
                return {failed: true, failure: {phase, message: String(error?.message || error), stack: String(error?.stack || ''), elapsedMs: performance.now() - started}, progress};
              } finally {guest.close();}
            }, {
              appUrl: new URL(relative(variant === 'control' ? control : candidate), base).href,
              manifestUrl: new URL(relative(manifestPath), base).href,
              hostUrl: new URL('runtime/luajit/host.mjs', base).href,
              source, samples, deadlineMs,
            });
            metadata.results.push({engine, version: browser.version(), round, variant, hostLoadBefore, hostLoadAfter: os.loadavg(), ...result, browserErrors: errors});
            record();
            console.log(JSON.stringify({engine, round, variant, failed: result.failed || false, startupMs: result.startupMs,
              summary: result.summary?.map(({samples, ...item}) => item), failure: result.failure}));
          } finally {await context.close();}
        }
      } finally {await browser.close();}
    }
  }
  const canonical = value => Array.isArray(value) ? value.map(canonical)
    : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
  const oracle = result => JSON.stringify(canonical({compile: result.compileDigests, diagnostics: result.diagnosticDigests, hover: result.hoverResponse, invalid: result.importedTypeChecks}));
  const passed = metadata.results.filter(result => !result.failed && !result.browserErrors.length);
  metadata.responseEquivalence = passed.every(result => oracle(result) === oracle(passed[0]));
  metadata.failedSessions = metadata.results.length - passed.length;
  metadata.ok = metadata.failedSessions === 0 && metadata.responseEquivalence;
  record();
  if (!metadata.ok) process.exitCode = 1;
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
