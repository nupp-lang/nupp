import {chromium,firefox,webkit} from 'playwright';
import {writeFileSync} from 'node:fs';
const [url, output] = process.argv.slice(2);
const results=[];
for(const engine of (process.env.NUPP_TEST_BROWSERS || 'chromium,firefox,webkit').split(',')) {
 const browser=await ({chromium,firefox,webkit}[engine]).launch({headless:true,...(engine==='chromium'?{channel:'chrome'}:{})});
 try {
  const page=await browser.newPage();
  // An inert same-origin page avoids running the UI's compiler alongside probes.
  await page.goto(new URL('performance-empty.html',url).href);
  for(const backend of ['luajit','lua51']) {
   console.log(engine,backend);
   const result=await page.evaluate(async backend=>{
    const begin=performance.now();
    const worker=new Worker(backend==='luajit'?'./worker.js':'./legacy-worker.js',{type:'module'});
    let id=0;
    try {
     await new Promise((resolve,reject)=>{worker.onmessage=({data})=>{if(data.type==='ready')resolve();if(data.type==='boot-error')reject(new Error(data.message));};worker.onerror=e=>reject(new Error(e.message));});
     const startupMs=performance.now()-begin;
     const request=body=>new Promise((resolve,reject)=>{const current=++id;worker.onmessage=({data})=>{if(data.id!==current)return; if(data.ok)resolve(data);else reject(new Error(data.error));};worker.postMessage({id:current,...body});});
     const summary=[];
     for(const kind of ['check','compile','hover','edit','large-edit']) {
      const samples=[];
      for(let trial=-3;trial<30;trial++) {
       // Every edit changes the initializer, including warm-up; no identical-source cache can answer it.
       const source=kind==='large-edit'?'local values={'+Array.from({length:2048},(_,i)=>i+Math.max(0,trial)+5).join(',')+'};return values[1]':`local answer: integer = ${trial+5}\nreturn answer`;
       const started=performance.now();
       const response=await request({kind:kind==='edit'||kind==='large-edit'?'check':kind,source,filename:'performance.nupp',offset:7,options:{dialect:backend,strict:true,optimize:true}});
       if(response.diagnostics?.some(x=>x.severity==='error'))throw new Error(JSON.stringify(response));
       if(trial>=0)samples.push(performance.now()-started);
      }
      const ordered=[...samples].sort((a,b)=>a-b);
      summary.push({kind,samples,p50Ms:ordered[14],p95Ms:ordered[28]});
     }
     return {startupMs,summary};
    } finally {worker.terminate();}
   },backend);
   results.push({engine,version:browser.version(),backend,...result});
   writeFileSync(output,JSON.stringify({scope:'Retained production compiler worker; 30 samples after 3 warmups; edits change every request; host performance.now round trip',results},null,2)+'\n');
  }
 } finally{await browser.close();}
}
