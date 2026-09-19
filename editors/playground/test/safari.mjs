// Run with the installed Safari, not Playwright's separately built WebKit.
// Start `safaridriver -p 4455`, then pass playground URL, fixture URL and output.
import {createServer} from 'node:http';
import {readFileSync, writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import os from 'node:os';

const [playground, fixtures, output] = process.argv.slice(2);
if (!playground || !fixtures || !output) throw new Error('usage: safari.mjs PLAYGROUND_URL FIXTURES_URL RESULT.json');
const endpoint = process.env.NUPP_SAFARI_DRIVER || 'http://127.0.0.1:4455';
const selection = process.env.NUPP_SAFARI_SCOPE || 'all';
if (!['all','ui','runtime'].includes(selection)) throw new Error('NUPP_SAFARI_SCOPE must be all, ui or runtime');
let session = process.env.NUPP_SAFARI_SESSION;
const results = [];
const metadata = {
  scope: 'Installed desktop Safari through Apple safaridriver. Narrow windows are not physical mobile-device validation. Local unthrottled startup timings include WebDriver polling.',
  revision: execFileSync('git', ['rev-parse', 'HEAD'], {encoding:'utf8'}).trim(),
  host: {platform:os.platform(), release:os.release(), arch:os.arch(), cpu:os.cpus()[0].model},
  startedAt: new Date().toISOString(),
  selection,
};
const record = () => writeFileSync(output, JSON.stringify({...metadata, results}, null, 2) + '\n');
async function command(method, route, body) {
  const response = await fetch(endpoint + route, {method,
    ...(body === undefined ? {} : {headers:{'content-type':'application/json'}, body:JSON.stringify(body)}),
    signal:AbortSignal.timeout(180000)});
  const {value} = await response.json();
  if (!response.ok || value?.error) throw new Error(`${route}: ${JSON.stringify(value)}`);
  return value;
}
const post = (route, body) => command('POST', `/session/${session}${route}`, body);
const evaluate = (script, ...args) => post('/execute/sync', {script, args});
async function wait(script, timeout = 120000) {
  const begin = performance.now();
  while (performance.now() - begin < timeout) {
    const value = await evaluate(script);
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error(`Timed out: ${script}\n${await evaluate('return document.body.innerText')}`);
}
async function element(selector) {
  const value = await post('/element', {using:'css selector', value:selector});
  return value['element-6066-11e4-a52e-4f735466cecf'];
}
const click = async selector => post(`/element/${await element(selector)}/click`, {});
async function navigate(url) {
  await post('/url', {url});
  await evaluate(`window.__safariErrors=[];
    addEventListener('error',e=>window.__safariErrors.push(String(e.message)));
    addEventListener('unhandledrejection',e=>window.__safariErrors.push(String(e.reason)));`);
}
const ready = () => wait("const b=document.querySelector('#compile-button');return b && !b.disabled && !document.body.classList.contains('is-busy')");
async function edit(source) {
  const id = await element('#source-editor .cm-content');
  await post(`/element/${id}/click`, {});
  await post('/actions', {actions:[{type:'key', id:'keyboard', actions:[
    {type:'keyDown', value:'\uE03D'}, {type:'keyDown', value:'a'},
    {type:'keyUp', value:'a'}, {type:'keyUp', value:'\uE03D'},
  ]}]});
  await post(`/element/${id}/value`, {text:source});
}
async function run(expected) {
  await ready(); await click('#compile-button');
  await wait("return document.querySelector('#output-summary')?.textContent==='ran'");
  const text = await evaluate("return document.querySelector('#output-main, #output-editor .cm-content')?.textContent");
  if (!text.includes(expected)) throw new Error(`Missing ${expected}: ${text}`);
}
async function check(name, action) {
  console.log(`Safari: ${name}`);
  const begin = performance.now();
  try {
    const details = await action();
    const errors = await evaluate('return window.__safariErrors || []');
    if (errors.length) throw new Error(errors.join('\n'));
    results.push({name, ok:true, elapsedMs:performance.now()-begin, ...details}); record();
  } catch (error) {
    results.push({name, ok:false, elapsedMs:performance.now()-begin, error:String(error.stack || error)});
    metadata.ok = false; record(); throw error;
  }
}
const fixture = readFileSync(new URL('../../../tests/wasm-aot/browser/http-response.json', import.meta.url));
const server = createServer((request, response) => {
  response.setHeader('Access-Control-Allow-Origin', '*');
  response.setHeader('Content-Type', 'application/json');
  response.writeHead(request.url === '/http-response.json' ? 200 : 404);
  response.end(request.url === '/http-response.json' ? fixture : '{}');
});
try {
  if (!session) {
    const created = await command('POST', '/session', {capabilities:{alwaysMatch:{browserName:'safari'}}});
    session = created.sessionId;
    metadata.capabilities = created.capabilities;
  }
  await post('/timeouts', {script:180000, pageLoad:180000, implicit:0});
  await new Promise((resolve,reject) => {server.once('error',reject);server.listen(8791,'127.0.0.1',resolve);});
  await navigate(playground);
  metadata.userAgent = await evaluate('return navigator.userAgent');
  metadata.crossOriginIsolated = await evaluate('return crossOriginIsolated');
  metadata.playgroundAssets = await fetch(new URL('nupp-playground-assets.json', playground)).then(r => r.json());
  const manifestText = await fetch(new URL('guest-manifest.json', fixtures)).then(r => r.text());
  metadata.guest = {buildKey:JSON.parse(manifestText).buildKey, manifestSha256:createHash('sha256').update(manifestText).digest('hex')};
  if (selection !== 'runtime') {
  await check('playground tour', async () => {await run('pay rent is high priority');});
  await check('stop infinite loop and run again', async () => {
    await edit('while true do end'); await ready(); await click('#compile-button');
    await wait("return document.querySelector('#output-summary')?.textContent==='running…'");
    const begin=performance.now(); await click('#compile-button');
    await wait("return document.querySelector('#output-main, #output-editor .cm-content')?.textContent.includes('Program stopped')");
    const cancelMs=performance.now()-begin;
    if(cancelMs>1000)throw new Error(`Slow cancellation: ${cancelMs} ms`);
    await edit('print("after stop")'); await run('after stop');
    return {cancelMs};
  });
  await check('compatibility rejection and settings persistence', async () => {
    await click('#options-button');
    await evaluate("[...document.querySelectorAll('label')].find(e=>e.textContent.includes('Require stock Lua 5.1')).querySelector('input').click()");
    await edit('const answer = 42\nprint(answer)');
    await wait("return document.querySelector('#output-main, #output-editor .cm-content')?.textContent.includes('NUPP3013')");
    await post('/refresh', {}); await ready(); await click('#options-button');
    const checked=await evaluate("return [...document.querySelectorAll('label')].find(e=>e.textContent.includes('Require stock Lua 5.1')).querySelector('input').checked");
    if(!checked)throw new Error('Compatibility setting was lost');
    await evaluate("[...document.querySelectorAll('label')].find(e=>e.textContent.includes('Require stock Lua 5.1')).querySelector('input').click()");
    await click('#options-button');
  });
  await check('legacy and LuaJIT backend switch', async () => {
    for (const [dialect,source,expected] of [['lua51','print("legacy works")','legacy works'], ['luajit','print(require("bit").bor(1, 2))','3']]) {
      await evaluate("const s=document.querySelector('#dialect-select');s.value=arguments[0];s.dispatchEvent(new Event('change',{bubbles:true}))",dialect);
      await edit(source); await run(expected);
    }
  });
  await check('narrow embedded playground', async () => {
    const window=await post('/window/rect',{width:390,height:844});
    await navigate(new URL('embed.html',playground).href); await run('pay rent is high priority');
    const viewport=await evaluate('return {width:innerWidth,height:innerHeight}');
    writeFileSync(output.replace(/\.json$/, '-narrow.png'), Buffer.from(await command('GET',`/session/${session}/screenshot`),'base64'));
    return {window,viewport};
  });
  await check('documentation run, disconnect and reconnect', async () => {
    await navigate(new URL('performance-empty.html',playground).href);
    await evaluate(`import('./doc-app.js').then(()=>{
      const editor=document.createElement('nupp-playground');editor.id='doc-test';
      editor.setAttribute('data-source',encodeURIComponent('print("documentation run")'));document.body.append(editor);
    })`);
    await wait("return document.querySelector('#doc-test')?.shadowRoot?.querySelector('button.run')");
    const docRun=()=>evaluate("document.querySelector('#doc-test').shadowRoot.querySelector('button.run').click()");
    const replace=source=>evaluate("const e=document.querySelector('#doc-test');e.remove();e.setAttribute('data-source',encodeURIComponent(arguments[0]));document.body.append(e)",source);
    await docRun();
    await wait("return document.querySelector('#doc-test').shadowRoot.querySelector('.output-main').textContent.includes('documentation run')");
    await replace('while true do end'); await docRun();
    await wait("return document.querySelector('#doc-test').shadowRoot.querySelector('.output-summary').textContent==='running…'");
    await replace('print("reconnected")'); await docRun();
    await wait("return document.querySelector('#doc-test').shadowRoot.querySelector('.output-main').textContent.includes('reconnected')");
  });
  }
  const pages=['smoke.html','compiler.html','application.html','recovery.html','lifecycle.html',...['aot','native','http','platform','workers','gpu'].map(name=>`packaged.html?app=${name}`)];
  if (selection !== 'ui') for(const page of pages) await check(page, async () => {
    await navigate(new URL(page,fixtures).href);
    await wait("return ['passed','failed'].includes(document.querySelector('#result')?.dataset.status)",180000);
    const result=JSON.parse(await evaluate("return document.querySelector('#result').textContent"));
    if(!result.ok)throw new Error(JSON.stringify(result));
    return {result};
  });
  metadata.ok=true; metadata.completedAt=new Date().toISOString(); record();
} finally {
  if(session)await command('DELETE',`/session/${session}`).catch(console.error);
  server.closeAllConnections();
  if(server.listening)await new Promise(resolve=>server.close(resolve));
}
