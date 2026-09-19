import {startGuest} from './guest-runtime.mjs';
const output = document.querySelector('#result');
const terminal = document.querySelector('#terminal');
try {
  let busySeen = false, abortAt;
  const controller = new AbortController();
  const busy = startGuest({appUrl:'./latency.lua',config:{mode:'compiler',jit:false,slim:true},
    signal:controller.signal,deadlineMs:30000,
    effectHandlers:{'compiler-request':()=>({kind:'busy',count:1})},
    onProgress: message => {
      if (message.log) terminal.textContent = message.log;
      if (!busySeen && message.log?.includes('COMPILER_BUSY_BEGIN')) {
        busySeen=true;
        setTimeout(()=>{abortAt=performance.now();controller.abort(new Error('busy request cancelled'));},25);
      }
    },
  });
  let busyError;
  try { await busy.result; } catch (error) { busyError=error; }
  const abortMs=performance.now()-abortAt;
  if (!busySeen || !/busy request cancelled/.test(String(busyError))) throw busyError || new Error('Busy cancellation not observed');
  let release;
  const staleController = new AbortController();
  const stale = startGuest({appUrl:'./latency.lua',config:{mode:'compiler',jit:false,slim:true},
    signal:staleController.signal,deadlineMs:30000,
    effectHandlers:{'compiler-request':()=> new Promise(resolve=>{
      release=resolve;
      setTimeout(()=>staleController.abort(new Error('pending request cancelled')),25);
    })},
  });
  let staleError;
  try {await stale.result;} catch(error){staleError=error;}
  if (!release || !/pending request cancelled/.test(String(staleError))) throw staleError || new Error('Pending request did not cancel');
  release({kind:'check',count:1});
  await new Promise(resolve=>setTimeout(resolve,50));
  output.textContent=JSON.stringify({ok:true,busySeen,abortMs,lateResponseDiscarded:true,
    recovery:'Worker termination discards the compiler VM; the next request requires a fresh boot.'});
  output.dataset.status='passed';
} catch(error) {
  output.textContent=JSON.stringify({ok:false,error:String(error.stack || error)});
  output.dataset.status='failed';
}
