import {createCompilerHost} from './wasm-runtime.js';
const digest = (await (await fetch('./compiler-digest.txt')).text()).trim();
const host = await createCompilerHost({
  moduleUrl: new URL('./nupp-playground.mjs', import.meta.url).href,
  wasmUrl: new URL('./nupp-playground.wasm', import.meta.url).href,
  compilerUrl: './nupp-compiler.lua', expectedDigest: digest,
});
postMessage({result: {loadedMs: host.timings}});
onmessage = ({data: request}) => {
  if (request.stop) { postMessage({done:true}); return; }
  try {
    const started = performance.now();
    const answers = [];
    for (let i=1;i<=request.count;i++) {
      if (request.kind === 'noop') answers.push({bytes:request.padding.length});
      else {
        let source = request.source || 'local value: number = 1; return value';
        if (request.kind === 'edit') source = source.replace('= 1', '= ' + i);
        answers.push(host.request({kind:request.kind === 'edit' ? 'check' : request.kind,
          source,filename:'latency.g.nupp',offset:7,options:{dialect:'lua51'}}));
      }
    }
    postMessage({result:{count:request.count,answers,sampledWallMs:performance.now()-started}});
  } catch (error) { postMessage({error:String(error.stack || error)}); }
};
