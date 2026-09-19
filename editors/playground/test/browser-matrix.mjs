import {chromium, firefox, webkit} from 'playwright';
import {createServer} from 'node:http';
import {writeFileSync, readFileSync} from 'node:fs';
const [base, output] = process.argv.slice(2);
if (!base || !output) throw new Error('usage: browser-matrix.mjs URL RESULT.json');
const selected = (process.env.NUPP_TEST_BROWSERS || 'chromium,firefox,webkit').split(',');
const results = [];
const tests = ['smoke.html', 'compiler.html', 'application.html', 'recovery.html', 'lifecycle.html', ...['aot','native','http','platform','workers','gpu'].map(name=>`packaged.html?app=${name}`)];
const record = () => writeFileSync(output, JSON.stringify({ok:results.length === selected.length * tests.length && results.every(x => x.ok && !x.errors.length), scope:'Desktop browser engine conformance; not physical mobile-device acceptance', results}, null, 2)+'\n');
// Request interception breaks blob workers in Playwright WebKit. A real HTTP
// endpoint also exercises fetch and CORS instead of replacing the browser's response.
const fixture = readFileSync(new URL('../../../tests/wasm-aot/browser/http-response.json',import.meta.url));
const server = createServer((request, response) => {
  response.setHeader('Access-Control-Allow-Origin', '*');
  response.setHeader('Content-Type', 'application/json');
  response.writeHead(request.url === '/http-response.json' ? 200 : 404);
  response.end(request.url === '/http-response.json' ? fixture : '{}');
});
await new Promise((resolve, reject) => {server.once('error', reject);server.listen(8791, '127.0.0.1', resolve);});
try {
  for (const name of selected) {
    const engine = {chromium, firefox, webkit}[name];
    const browser = await engine.launch({headless:true, ...(name === 'chromium' ? {channel:'chrome',args:['--no-sandbox','--enable-unsafe-webgpu','--enable-unsafe-swiftshader','--use-angle=swiftshader']} : {})});
    try {
      const context = await browser.newContext();
      for (const file of tests) {
        const page = await context.newPage(), errors = [];
        page.on('pageerror', error => errors.push(String(error)));
        console.log(`${name}: ${file}`);
        let result;
        try {
          await page.goto(new URL(file, base).href);
          await page.waitForFunction(() => ['passed','failed'].includes(document.querySelector('#result')?.dataset.status), null, {timeout:180000});
          result = await page.locator('#result').textContent().then(JSON.parse);
          if (name === 'chromium' && result.unsupported) result.ok = false;
        } catch (error) {
          result = {ok:false, error:String(error), body:await page.locator('body').innerText().catch(()=>'Unavailable')};
        } finally { await page.close(); }
        results.push({engine:name, version:browser.version(), test:file, ...result, errors});
        record();
        if (!result.ok || errors.length) throw new Error(`${name} ${file}: ${JSON.stringify(result)} ${errors.join('\n')}`);
      }
      await context.close();
    } finally { await browser.close(); }
  }
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
