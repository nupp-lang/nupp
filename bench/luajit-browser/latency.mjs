import {startGuest} from './guest-runtime.mjs';
const output = document.querySelector('#result');
const terminal = document.querySelector('#terminal');
const query = new URL(location.href).searchParams;
const backend = query.get('backend') || 'luajit';
const trials = Number(query.get('trials') || 30);
const samples = [];
const phaseMarkers = [];
const schedule = [];
for (const kind of ['noop', 'check', 'compile', 'hover', 'edit', 'large-check', 'import-check']) {
  for (const count of (kind === 'large-check' || kind === 'import-check' ? [1, 4] : [1, 16])) {
    for (const bytes of (kind === 'noop' ? [0, 4096, 65536] : [0])) {
      for (let trial = -2; trial < trials; trial++) schedule.push({kind, count, bytes, trial});
    }
  }
}
const quantile = (values, p) => [...values].sort((a,b) => a-b)[Math.ceil(values.length*p)-1];
let sentAt, previous, index = 0, startup;
try {
  const handle = ({result}) => {
      if (!startup) startup = result;
      if (previous) {
        const elapsedMs = performance.now() - sentAt;
        if (result.count !== previous.count) throw new Error('Missing batch results');
        for (const answer of Object.values(result.answers)) {
          if (answer.reason || Object.values(answer.diagnostics || {}).some(d => d.severity === 'error')) {
            throw new Error('Compiler returned a diagnostic: ' + JSON.stringify(answer));
          }
        }
        if (previous.trial >= 0) samples.push({...previous, elapsedMs,
          sampledWallMs: result.sampledWallMs, guestCpuMs: result.guestCpuMs});
      }
      previous = schedule[index++];
      if (!previous) return {stop: true};
      terminal.textContent = JSON.stringify(previous);
      sentAt = performance.now();
      const source = previous.kind === 'large-check' ? 'local values={' + Array.from({length:2048}, (_,i)=>i+1).join(',') + '}; return values[1]'
        : previous.kind === 'import-check' ? 'local text = require("nupp.text"); return text' : undefined;
      return {...previous, source, kind: source ? 'check' : previous.kind, padding: 'x'.repeat(previous.bytes)};
  };
  if (backend === 'lua51') {
    const worker = new Worker('./latency-portable.mjs', {type:'module'});
    try {
      await new Promise((resolve,reject) => {
        worker.onerror = event => reject(new Error(event.message));
        worker.onmessage = ({data}) => {
          if (data.done) resolve();
          else if (data.error) reject(new Error(data.error));
          else { try { worker.postMessage(handle(data)); } catch (error) { reject(error); } }
        };
      });
    } finally { worker.terminate(); }
  } else {
    await startGuest({appUrl:'./latency.lua', config:{mode:'compiler',jit:false,slim:true,nativeCompiler:query.has('native'), direct:query.has('direct'), compilerTransport:query.has('transport'), timingProbe:query.has('phases'),
        bundle:query.has('native') ? '/nupp/native-compiler.ljbc' : undefined},
      deadlineMs:240000, effectHandlers:{'compiler-request':handle},
      onProgress:message => {if(message.log) terminal.textContent=message.log; if(message.type === 'phase') phaseMarkers.push(message);},
    }).result;
  }
  const groups = new Map();
  for (const sample of samples) {
    const key = `${sample.kind}/${sample.count}/${sample.bytes}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(sample);
  }
  const summary = [...groups].map(([key, values]) => ({key,
    p50Ms: quantile(values.map(s => s.elapsedMs), .5), p95Ms: quantile(values.map(s => s.elapsedMs), .95),
    msPerOperation: values.reduce((sum,s) => sum+s.elapsedMs,0) / values.reduce((sum,s) => sum+s.count,0),
    zeroGuestTimerSamples: values.filter(s => s.sampledWallMs === 0).length,
    sampledWallP50Ms: quantile(values.map(s => s.sampledWallMs), .5),
  }));
  output.textContent = JSON.stringify({ok:true, backend, direct:query.has('direct'), compilerTransport:query.has('transport'), startup, summary, samples, phaseMarkers});
  output.dataset.status = 'passed';
} catch (error) {
  output.textContent = JSON.stringify({ok:false, error:String(error.stack || error), samples});
  output.dataset.status = 'failed';
}
