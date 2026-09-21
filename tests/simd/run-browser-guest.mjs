import {createHash} from 'node:crypto';
import {createReadStream, existsSync, readFileSync, writeFileSync} from 'node:fs';
import {createServer} from 'node:http';
import path from 'node:path';
import {chromium} from '../../editors/playground/node_modules/playwright/index.mjs';
import {packageBrowserApp} from '../../runtime/luajit/package-browser-app.mjs';

const [projectArg, guestArg, outputArg, route = 'simd'] = process.argv.slice(2);
if (!projectArg || !guestArg || !outputArg || !['simd', 'scalar-c'].includes(route)) {
  throw new Error('usage: run-browser-guest.mjs PROJECT GUEST OUTPUT simd|scalar-c');
}
const project = path.resolve(projectArg), guest = path.resolve(guestArg), output = path.resolve(outputArg);
const manifest = await packageBrowserApp({project, target:'app', output, guest, prebuilt:true});
const corpus = JSON.parse(readFileSync(path.join(project, 'corpus.json'), 'utf8'));
// Allow the larger owned corpora a bounded ten minutes on loaded runners.
const deadlineMs = ['utf8simd', 'simd-json'].includes(corpus.algorithm) ? 600000 : 240000;
const entries = manifest.kernels.flatMap(kernel => kernel.entries.map(entry => ({...entry, unit:kernel.unit})));
const symbols = {};
const executedEntries = [];
for (const [module, names] of Object.entries(corpus.probes)) {
  const suffixes = [`/${module}.simd128.c`, `/${module}.g.simd128.c`];
  const units = manifest.kernels.filter(kernel => suffixes.some(suffix => kernel.source?.endsWith(suffix)));
  if (units.length !== 1) throw new Error(`Missing unique independent Wasm unit for ${module}`);
  for (const name of names) {
    const lowered = name.replace(/[A-Z]/g, letter => '_' + letter.toLowerCase());
    const matches = entries.filter(entry => entry.unit === units[0].unit &&
      [name, lowered].some(suffix => entry.symbol.endsWith('_' + suffix)));
    if (matches.length !== 1) throw new Error(`Missing unique independent Wasm entry for ${module}.${name}`);
    const key = `${module}.${name}`;
    symbols[key] = matches[0].symbol;
    executedEntries.push({key, symbol:matches[0].symbol, unit:matches[0].unit,
      entryMode:corpus.algorithm === 'fused-json' ? 'builder' : 'kernel'});
  }
}
if (!Object.keys(symbols).length) throw new Error('Empty Wasm probe inventory');

writeFileSync(path.join(output, 'runner.html'), '<!doctype html><meta charset="utf-8"><pre id="result" data-status="running"></pre><script type="module" src="runner.mjs"></script>');
writeFileSync(path.join(output, 'runner.mjs'), `
import {runPackagedNuppLuaJITApp} from './app-runtime.mjs';
const output = document.querySelector('#result');
try {
  const result = await runPackagedNuppLuaJITApp('./nupp-browser-app.json', {limits:{
    maxEffects:1000000, maxEffectBytes:268435456, maxResponseBytes:268435456,
    maxStorageValueBytes:1048576, deadlineMs:${deadlineMs},
  }});
  if (!result || !Number.isFinite(result.cases) || result.cases <= 0) throw new Error('SIMD corpus returned no cases');
  output.textContent = JSON.stringify({ok:true, result}); output.dataset.status = 'passed';
} catch (error) {
  output.textContent = JSON.stringify({ok:false,error:String(error),stack:error.stack}); output.dataset.status = 'failed';
}
`);
const server = createServer((request, response) => {
  try {
    const file = path.resolve(output, '.' + decodeURIComponent(new URL(request.url, 'http://localhost').pathname));
    if (!file.startsWith(output + path.sep) || !existsSync(file)) throw new Error('not found');
    response.setHeader('Content-Type', file.endsWith('.mjs') ? 'text/javascript' : file.endsWith('.html') ? 'text/html' : 'application/octet-stream');
    createReadStream(file).pipe(response);
  } catch { response.writeHead(404); response.end('not found'); }
});
await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
let browser;
try {
  browser = await chromium.launch({headless:true, args:['--no-sandbox','--disable-dev-shm-usage']});
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${server.address().port}/runner.html`);
  await page.waitForFunction(() => ['passed','failed'].includes(document.querySelector('#result')?.dataset.status), null, {timeout:deadlineMs});
  const browserResult = JSON.parse(await page.locator('#result').textContent());
  if (!browserResult.ok) throw new Error(JSON.stringify(browserResult));
  const digest = file => createHash('sha256').update(readFileSync(file)).digest('hex');
  const artifacts = manifest.kernels.map(kernel => ({...kernel, sha256:digest(path.join(output, kernel.file))}));
  const hostArtifacts = [manifest.guest, 'app-runtime.mjs'].map(name => ({name, sha256:digest(path.join(output, name))}));
  const scalarSelectionPath = path.join(project, 'scalar-selection.json');
  const report = {ok:true, tier:'simd128', executionPath:route, runtime:'LuaJIT browser guest',
    cases:browserResult.result.cases, probes:Object.keys(symbols).length,
    nativeCalls:Object.keys(symbols).length, callCountFloor:true, symbols, entries:executedEntries,
    appSha256:digest(path.join(output, manifest.app)), hostArtifacts, artifacts,
    randomFingerprint:browserResult.result.randomFingerprint, coverage:corpus.coverage,
    scalarSelection:existsSync(scalarSelectionPath) ? JSON.parse(readFileSync(scalarSelectionPath, 'utf8')) : null};
  writeFileSync(path.join(project, 'result.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report));
} finally {
  await browser?.close();
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
