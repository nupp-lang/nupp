import {chromium,firefox,webkit} from 'playwright';
import {writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import os from 'node:os';
const [url, output] = process.argv.slice(2);
if(!url || !output)throw new Error('usage: compiler-performance.mjs URL RESULT.json');
const results=[], repetitions=Number(process.env.NUPP_BENCH_REPETITIONS || 3);
const metadata={scope:'Production LuaJIT compiler workers across fresh browser contexts; 30 samples after 3 warmups per request kind; edits change every request; host performance.now round trip. Large edit is a 2048-element literal, not a large project import.',commit:execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim(),host:{platform:os.platform(),arch:os.arch(),cpu:os.cpus()[0].model,memoryBytes:os.totalmem()},repetitions};
for(const engine of (process.env.NUPP_TEST_BROWSERS || 'chromium,firefox,webkit').split(',')) {
 for(let round=0;round<repetitions;round++) {
  const browser=await ({chromium,firefox,webkit}[engine]).launch({headless:true,...(engine==='chromium'?{channel:'chrome'}:{})});
  try {
   const page=await browser.newPage();
   await page.goto(new URL('performance-empty.html',url).href);
   for(const backend of ['luajit']) {
    console.log(engine,round,backend);
    const result=await page.evaluate(async backend=>{
     const begin=performance.now();
     const worker=new Worker('./worker.js',{type:'module'});
     let id=0;
     const bounded=action=>new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>reject(new Error('Compiler request timeout')),120000);
      action(value=>{clearTimeout(timer);resolve(value);},error=>{clearTimeout(timer);reject(error);});
     });
     try {
      await bounded((resolve,reject)=>{worker.onmessage=({data})=>{if(data.type==='ready')resolve();if(data.type==='boot-error')reject(new Error(data.message));};worker.onerror=e=>reject(new Error(e.message));});
      const startupMs=performance.now()-begin;
      const request=body=>bounded((resolve,reject)=>{const current=++id;worker.onmessage=({data})=>{if(data.id!==current)return;if(data.ok)resolve(data);else reject(new Error(data.error));};worker.postMessage({id:current,...body});});
      const summary=[];
      for(const kind of ['check','compile','hover','edit','large-edit']) {
       const samples=[];
       let firstRequestMs;
       for(let trial=-3;trial<30;trial++) {
        const source=kind==='large-edit'?'local values={'+Array.from({length:2048},(_,i)=>i+trial+5).join(',')+'};return values[1]':`local answer: integer = ${trial+5}\nreturn answer`;
        const started=performance.now();
        const response=await request({kind:kind==='edit'||kind==='large-edit'?'check':kind,source,filename:'performance.nupp',offset:7,options:{dialect:backend,strict:true,optimize:true}});
        if(response.diagnostics?.some(x=>x.severity==='error'))throw new Error(JSON.stringify(response));
        const elapsed=performance.now()-started;
        if(trial===-3)firstRequestMs=elapsed;
        if(trial>=0)samples.push(elapsed);
       }
       const ordered=[...samples].sort((a,b)=>a-b);
       summary.push({kind,firstRequestMs,samples,p50Ms:ordered[14],p95Ms:ordered[28]});
      }
      return {startupMs,summary};
     } finally {worker.terminate();}
    },backend);
    results.push({engine,round,version:browser.version(),backend,...result});
    writeFileSync(output,JSON.stringify({...metadata,results},null,2)+'\n');
   }
  } finally{await browser.close();}
 }
}
