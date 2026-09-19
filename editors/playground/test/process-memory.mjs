import {chromium} from 'playwright';
import {execFileSync} from 'node:child_process';
import {writeFileSync,readFileSync,mkdtempSync,rmSync} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
const [url, output] = process.argv.slice(2);
if(!url || !output)throw new Error('usage: process-memory.mjs URL RESULT.json');
const temporary=mkdtempSync(path.join(os.tmpdir(),'nupp-browser-memory-')),results=[];
try {
 for(const backend of ['luajit','lua51']) {
  const server=await chromium.launchServer({headless:true,channel:'chrome'});
  const root=server.process().pid, samples=[],begin=performance.now();
  let phase='baseline';
  function sample() {
   const rows=execFileSync('ps',['-axo','pid=,ppid=,rss='],{encoding:'utf8'}).trim().split('\n').map(x=>x.trim().split(/\s+/).map(Number));
   const owned=new Set([root]);
   let changed=true;
   while(changed){changed=false;for(const [pid,parent] of rows)if(owned.has(parent)&&!owned.has(pid)){owned.add(pid);changed=true;}}
   const processes=rows.filter(([pid])=>owned.has(pid));
   const row={phase,elapsedMs:performance.now()-begin,rssBytes:processes.reduce((sum,x)=>sum+x[2]*1024,0),processes:processes.length};
   if(os.platform()==='darwin') {
    const file=path.join(temporary,'footprint.json');
    try {
     execFileSync('/usr/bin/footprint',['--noCategories','-f','bytes','-j',file,...processes.map(x=>String(x[0]))],{stdio:'ignore'});
     const result=JSON.parse(readFileSync(file,'utf8'));
     if(result.errors.length)throw new Error(JSON.stringify(result.errors));
     row.footprintBytes=result['total footprint'];
    } catch(error) {row.footprintError=String(error);}
   }
   samples.push(row);return row;
  }
  const timer=setInterval(sample,100);
  let browser;
  try {
   browser=await chromium.connect(server.wsEndpoint());
   const page=await browser.newPage();
   await page.goto(new URL('performance-empty.html',url).href);
   await page.evaluate(backend=>localStorage.setItem('nupp-playground-options-v1',JSON.stringify({dialect:backend})),backend);
   const baseline=sample();
   phase='compiler-startup';
   await page.goto(url);
   await page.waitForFunction(()=>document.querySelector('#status')?.textContent.includes('checked'),null,{timeout:120000});
   const compilerReady=sample();
   phase='first-run';
   await page.locator('#compile-button').click();
   await page.waitForFunction(()=>document.querySelector('#output-summary')?.textContent==='ran',null,{timeout:60000});
   const afterRun=sample();
   phase='teardown';
   await page.close();
   const blank=await browser.newPage();await blank.goto('about:blank');
   await new Promise(resolve=>setTimeout(resolve,1000));
   const afterTeardown=sample();
   results.push({backend,version:browser.version(),baseline,compilerReady,afterRun,afterTeardown,peakRssBytes:Math.max(...samples.map(x=>x.rssBytes)),peakFootprintBytes:samples.every(x=>Number.isFinite(x.footprintBytes))?Math.max(...samples.map(x=>x.footprintBytes)):null,samples});
   writeFileSync(output,JSON.stringify({scope:'Each backend uses a fresh headless Chromium process tree sampled every 100 ms. RSS sums shared pages more than once. On macOS footprintBytes is the footprint tool total for that process family. Includes browser overhead, compiler and transient application VM. Teardown is one second after closing the page. This is desktop memory accounting, not mobile acceptance or a VM-size limit.',host:{platform:os.platform(),arch:os.arch(),cpu:os.cpus()[0].model},results},null,2)+'\n');
  } finally {clearInterval(timer);await browser?.close();await server.close();}
 }
} finally {rmSync(temporary,{recursive:true,force:true});}
