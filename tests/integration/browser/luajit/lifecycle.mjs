import {createGuest} from './host.mjs';
const output = document.querySelector('#result'), encoder = new TextEncoder();
const options = {manifestUrl:'./guest-manifest.json',deadlineMs:30000};
try {
  const runs = [];
  for (let round=0;round<5;round++) {
    const abort = new AbortController(); let requested;
    const guest = createGuest({...options,signal:abort.signal,app:encoder.encode('while true do end'),
      onProgress(message) {if(message.type==='ready')setTimeout(()=>{requested=performance.now();abort.abort(new Error('intentional cancellation'));},50);}});
    try {await guest.receive();throw new Error('Busy guest was not cancelled');}
    catch(error) {if(!String(error).includes('intentional cancellation'))throw error;}
    finally {guest.close();}
    const cancelMs=performance.now()-requested;
    if(cancelMs>1000)throw new Error(`Cancellation took ${cancelMs} ms`);
    const next=createGuest({...options,app:encoder.encode(`assert(require('bit').bor(1,2)==3); return ${round}`)});
    try {const frame=await next.receive();if(frame.type!=='done'||!frame.result.ok)throw new Error(JSON.stringify(frame));}
    finally {next.close();}
    runs.push({round,cancelMs});
  }
  // Touch more memory than the 64 MiB guest can supply. Failure must reach the
  // host, and the next VM must remain usable; this is not a mobile RSS claim.
  const pressure=createGuest({...options,app:encoder.encode('local ffi=require("ffi");local held={} for i=1,64 do local p=ffi.new("uint8_t[?]",4*1024*1024);ffi.fill(p,4*1024*1024,1);held[i]=p end return #held')});
  let pressureError;
  try {
    const frame=await pressure.receive();
    if(!frame.result?.ok)pressureError=frame.result?.error;
  } catch(error) {pressureError=String(error);}
  finally {pressure.close();}
  if(!pressureError || /timed out/.test(pressureError))throw new Error(`Memory pressure was not reported: ${pressureError}`);
  const recovery=createGuest({...options,app:encoder.encode('return require("string.buffer").new():put("recovered"):get()')});
  try {const frame=await recovery.receive();if(!frame.result?.ok || frame.result.value!=='recovered')throw new Error(JSON.stringify(frame));}
  finally {recovery.close();}
  output.textContent=JSON.stringify({ok:true,runs,pressureError});output.dataset.status='passed';
} catch(error) {output.textContent=JSON.stringify({ok:false,error:String(error.stack||error)});output.dataset.status='failed';}
