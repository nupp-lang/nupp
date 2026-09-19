import {createGuest} from '../../runtime/luajit/host.mjs';
const out=document.querySelector('#result'), terminal=document.querySelector('#terminal');
const result={ok:true,scope:'Production compiler bytecode, real raw-source transport; alternating JIT mode; three warmups then 30 changing edits',runs:[]};
const app=new Uint8Array(await(await fetch('./compiler.ljbc')).arrayBuffer());
try {
 for(let round=0;round<3;round++) for(const jit of round%2?[true,false]:[false,true]) {
  terminal.textContent=JSON.stringify({round,jit});
  const start=performance.now(),g=createGuest({manifestUrl:'./guest-manifest.json',app,profile:'compiler',config:{mode:'compiler',jit},deadlineMs:120000});
  try {
   const ready=await g.receive();if(!ready.result.ready)throw new Error(JSON.stringify(ready));
   const run={round,jit,startupMs:performance.now()-start,cases:[]};
   for(const kind of ['edit','large-edit']) {
    const samples=[];
    for(let i=-3;i<30;i++) {
     const source=kind==='large-edit'?'local values={'+Array.from({length:2048},(_,n)=>n+i+5).join(',')+'};return values[1]':`local answer: integer = ${i+5}\nreturn answer`;
     const started=performance.now();g.respond({kind:'check',filename:'performance.nupp',options:{strict:true,optimize:true},payloadField:'source'},new TextEncoder().encode(source));
     const answer=await g.receive();if(!answer.result.ok||answer.result.response.diagnostics.some(x=>x.severity==='error'))throw new Error(JSON.stringify(answer));
     if(i>=0)samples.push(performance.now()-started);
    }
    const sorted=[...samples].sort((a,b)=>a-b);run.cases.push({kind,p50Ms:sorted[14],p95Ms:sorted[28],samples});
   }
   result.runs.push(run);out.textContent=JSON.stringify(result);
  }finally{g.close();}
 }
 out.dataset.status='passed';
}catch(e){out.textContent=JSON.stringify({...result,ok:false,error:String(e.stack||e)});out.dataset.status='failed';}
