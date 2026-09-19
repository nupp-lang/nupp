import {chromium, firefox, webkit} from 'playwright';
import {writeFileSync,readFileSync} from 'node:fs';
const [base, output] = process.argv.slice(2);
if (!base || !output) throw new Error('usage: browser-matrix.mjs URL RESULT.json');
const selected = (process.env.NUPP_TEST_BROWSERS || 'chromium,firefox,webkit').split(',');
const results = [];
for (const name of selected) {
  const engine = {chromium, firefox, webkit}[name];
  const browser = await engine.launch({headless:true, ...(name === 'chromium' ? {channel:'chrome',args:['--no-sandbox','--enable-unsafe-webgpu','--enable-unsafe-swiftshader','--use-angle=swiftshader']} : {})});
  try {
    const context = await browser.newContext();
    await context.route('http://127.0.0.1:8791/http-response.json', route => route.fulfill({status:200,contentType:'application/json',body:readFileSync(new URL('../../../tests/wasm-aot/browser/http-response.json',import.meta.url))}));
    for (const file of ['smoke.html', 'compiler.html', 'application.html', 'recovery.html', 'lifecycle.html', ...['aot','http','platform','workers','gpu'].map(name=>`packaged.html?app=${name}`)]) {
      const page = await context.newPage(), errors = [];
      page.on('pageerror', error => errors.push(String(error)));
      console.log(`${name}: ${file}`);
      let result;
      try {
        await page.goto(new URL(file, base).href);
        await page.waitForFunction(() => ['passed','failed'].includes(document.querySelector('#result')?.dataset.status), null, {timeout:180000});
        result = await page.locator('#result').textContent().then(JSON.parse);
        results.push({engine:name, version:browser.version(), test:file, ...result, errors});
        writeFileSync(output, JSON.stringify({ok:results.every(x => x.ok && !x.errors.length), scope:'Desktop browser engine conformance; not physical mobile-device acceptance', results}, null, 2)+'\n');
        if (!result.ok || errors.length || (name === 'chromium' && result.unsupported)) throw new Error(`${name} ${file}: ${JSON.stringify(result)} ${errors.join('\n')}`);
      } finally { await page.close(); }
    }
    await context.close();
  } finally { await browser.close(); }
}
