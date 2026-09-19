import {chromium,firefox,webkit} from 'playwright';
import {writeFileSync} from 'node:fs';
const [url, output] = process.argv.slice(2);
const results = [];
for (const engine of (process.env.NUPP_TEST_BROWSERS || 'chromium,firefox,webkit').split(',')) {
  const browser = await ({chromium,firefox,webkit}[engine]).launch({headless:true,...(engine==='chromium'?{channel:'chrome'}:{})});
  try {
    const context = await browser.newContext();
    const page = await context.newPage(), errors=[];
    page.on('pageerror', error=>errors.push(String(error)));
    const ready = () => page.waitForFunction(()=>{const button=document.querySelector('#compile-button');return button && !button.disabled && !document.body.classList.contains('is-busy');},null,{timeout:120000});
    const edit = async source => {
      const content=page.locator('#source-editor .cm-content');
      await content.click(); await page.keyboard.press('ControlOrMeta+A'); await page.keyboard.insertText(source);
    };
    const run = async expected => {
      await ready(); await page.locator('#compile-button').click();
      await page.waitForFunction(()=>document.querySelector('#output-summary')?.textContent==='ran',null,{timeout:30000});
      const actual=await page.locator('#output-main, #output-editor .cm-content').innerText();
      if(!actual.includes(expected))throw new Error(`Missing ${expected}: ${actual}`);
    };
    const response = await page.goto(url);
    if (!response.ok()) throw new Error(`Playground returned HTTP ${response.status()}: ${url}`);
    await run('pay rent is high priority');
    await page.screenshot({path:output.replace('.json',`-${engine}.png`),fullPage:true});
    await edit('while true do end'); await ready(); await page.locator('#compile-button').click();
    await page.waitForFunction(()=>document.querySelector('#output-summary')?.textContent==='running…');
    const started=performance.now(); await page.locator('#compile-button').click();
    await page.waitForFunction(()=>document.querySelector('#output-main, #output-editor .cm-content')?.textContent.includes('Program stopped'));
    const cancelMs=performance.now()-started;
    if(cancelMs>1000)throw new Error(`Slow cancellation: ${cancelMs} ms`);
    await edit('print("after stop")'); await run('after stop');
    await page.locator('#options-button').click();
    await page.getByLabel('Require stock Lua 5.1 compatibility').check();
    await edit('const answer = 42\nprint(answer)');
    await page.waitForFunction(()=>document.querySelector('#output-main, #output-editor .cm-content')?.textContent.includes('NUPP3013'));
    await page.reload(); await ready();
    await page.locator('#options-button').click();
    if(!await page.getByLabel('Require stock Lua 5.1 compatibility').isChecked())throw new Error('Compatibility setting was lost');
    await page.getByLabel('Require stock Lua 5.1 compatibility').uncheck();
    await page.locator('#options-button').click();
    await page.locator('#dialect-select').selectOption('lua51');
    await edit('print("legacy works")'); await run('legacy works');
    await page.locator('#dialect-select').selectOption('luajit');
    await edit('print(require("bit").bor(1, 2))'); await run('3');
    // The iframe remains usable at a narrow viewport, with a separately owned VM.
    await page.setViewportSize({width:390,height:844});
    await page.goto(new URL('embed.html',url).href); await run('pay rent is high priority');
    await page.screenshot({path:output.replace('.json',`-${engine}-narrow.png`),fullPage:true});
    await page.goto(new URL('performance-empty.html',url).href);
    await page.evaluate(async()=>{
      await import('./doc-app.js');
      const editor=document.createElement('nupp-playground');
      editor.id='doc-test';editor.setAttribute('data-source',encodeURIComponent('print("documentation run")'));
      document.body.append(editor);
    });
    const doc=page.locator('#doc-test');
    await doc.locator('button.run').click();
    await page.waitForFunction(()=>document.querySelector('#doc-test').shadowRoot.querySelector('.output-summary').textContent==='ran',null,{timeout:30000});
    if(!(await doc.locator('.output-main').innerText()).includes('documentation run'))throw new Error('Documentation result mismatch');
    await page.evaluate(()=>{
      const editor=document.querySelector('#doc-test');editor.remove();
      editor.setAttribute('data-source',encodeURIComponent('while true do end'));
      document.body.append(editor);
    });
    await doc.locator('button.run').click();
    await page.waitForFunction(()=>document.querySelector('#doc-test').shadowRoot.querySelector('.output-summary').textContent==='running…');
    await page.evaluate(()=>{
      const editor=document.querySelector('#doc-test');editor.remove();
      editor.setAttribute('data-source',encodeURIComponent('print("reconnected")'));
      document.body.append(editor);
    });
    await doc.locator('button.run').click();
    await page.waitForFunction(()=>document.querySelector('#doc-test').shadowRoot.querySelector('.output-main').textContent.includes('reconnected'),null,{timeout:30000});
    results.push({engine,version:browser.version(),cancelMs,checks:['tour','stop infinite loop','run after stop','compat rejection','stored settings','legacy and LuaJIT switch','narrow iframe','documentation run and disconnect/reconnect'],errors});
    writeFileSync(output,JSON.stringify({scope:'Desktop engines, including narrow viewport; not physical mobile-device acceptance',results},null,2)+'\n');
    if(errors.length)throw new Error(errors.join('\n'));
    await context.close();
  } finally {await browser.close();}
}
