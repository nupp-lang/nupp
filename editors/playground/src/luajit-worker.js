import {createCompiler} from '../../../runtime/luajit/host.mjs';
import {loadPackedAsset} from '../../../runtime/luajit/assets.mjs';
import {describeError} from './describe-error.js';
let compiler;
const queue = [];
let running = false;

async function boot() {
  postMessage({type: 'status', message: 'starting LuaJIT…'});
  const started = performance.now();
  const app = await loadPackedAsset(new URL(`./${__NUPP_LUAJIT_COMPILER__}`, import.meta.url),
    {sha256:__NUPP_LUAJIT_COMPILER_SHA256__, bytes:__NUPP_LUAJIT_COMPILER_BYTES__, decodedBytes:__NUPP_LUAJIT_COMPILER_DECODED_BYTES__});
  compiler = await createCompiler({manifestUrl: new URL(`./${__NUPP_LUAJIT_MANIFEST__}`, import.meta.url).href, app});
  postMessage({type: 'ready', timings: {startupMs: performance.now() - started}});
}

async function drain() {
  if (running) return;
  running = true;
  try {
    while (queue.length) {
      const message = queue.shift();
      try {
        const {id, ...request} = message;
        if (!compiler) throw new Error('The compiler is still loading');
        if (!['check', 'compile', 'hover'].includes(request.kind)) throw new Error('Unknown compiler request');
        if (typeof request.source === 'string' && new TextEncoder().encode(request.source).length > 1024 * 1024)
          throw new Error('Playground source exceeds 1048576 UTF-8 bytes');
        const response = await compiler.request(request);
        postMessage({id, ok: true, ...response});
      } catch (error) { postMessage({id: message.id, ok: false, error: String(error.message || error)}); }
    }
  } finally { running = false; }
}
self.onmessage = ({data}) => {
  if (data.kind === 'check') {
    for (let index = queue.length - 1; index >= 0; index--) {
      if (queue[index].kind !== 'check') break;
      const stale = queue.splice(index, 1)[0];
      postMessage({id: stale.id, ok: false, cancelled: true, error: 'Superseded by a newer edit'});
    }
  }
  if (queue.length >= 32) { postMessage({id: data.id, ok: false, error: 'Compiler request queue is full'}); return; }
  queue.push(data);
  drain();
};
boot().catch(error => postMessage({type: 'boot-error', message: describeError(error)}));
