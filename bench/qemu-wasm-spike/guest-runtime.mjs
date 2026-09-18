import {handleBrowserEffects} from './runtime/app-runtime.mjs';

// Present guest transfer leases through the existing browser handler ABI.
// Addresses below name a per-frame staging buffer, never guest pointers.
export function leaseAdapter(leases) {
  const entries = new Map();
  let size = 8;
  for (const lease of leases) {
    if (entries.has(lease.id) || !Number.isSafeInteger(lease.bytes) || lease.bytes < 0 ||
        !(lease.data instanceof ArrayBuffer) || lease.data.byteLength !== lease.bytes) {
      throw new Error('Invalid transferred lease');
    }
    entries.set(lease.id, {...lease, offset: size, released: false});
    size += Math.ceil(lease.bytes / 8) * 8;
    if (size > 17 * 1024 * 1024) throw new Error('Transfer allocation limit exceeded');
  }
  const bytes = new Uint8Array(size);
  for (const entry of entries.values()) bytes.set(new Uint8Array(entry.data), entry.offset);
  const active = id => { const entry = entries.get(id); return entry && !entry.released ? entry : undefined; };
  return {
    module: {
      HEAPU8: bytes,
      _nupp_wasm_lease_address: id => active(id)?.offset || 0,
      _nupp_wasm_lease_size: id => active(id)?.bytes || 0,
      _nupp_wasm_lease_writable: id => active(id)?.writable ? 1 : 0,
      _nupp_wasm_release_lease: id => { if (entries.has(id)) entries.get(id).released = true; },
    },
    writes: () => [...entries.values()].filter(entry => entry.writable).map(entry => ({
      id: entry.id, data: bytes.slice(entry.offset, entry.offset + entry.bytes).buffer,
    })),
    released: () => [...entries.values()].filter(entry => entry.released).map(entry => entry.id),
  };
}

export function startGuest({appUrl = './app.ljbc', config = {}, effectHandlers = {}, signal,
  storageName = 'nupp-qemu-integration', deadlineMs = 180000, resetLimits, onProgress = () => {}} = {}) {
  const worker = new Worker(new URL('./vm-worker.mjs', import.meta.url), {type: 'module'});
  const controller = new AbortController();
  const started = performance.now();
  const metrics = {frames: 0, effects: 0, effectBytes: 0, responseBytes: 0, copiedIn: 0, copiedOut: 0, hostEffectMs: [], guestIntervalsMs: []};
  const encoder = new TextEncoder();
  const options = {effectHandlers, signal: controller.signal, storageName,
    limitOverrides: {maxEffects: 10000, maxEffectBytes: 16 * 1024 * 1024,
      maxResponseBytes: 16 * 1024 * 1024, maxStorageValueBytes: 1024 * 1024, deadlineMs}};
  let resolve, reject, settled = false, lastResponse, timer, clockTimer, lastLog = '';
  let turnFrames = 0, turnEffects = 0, turnInputBytes = 0, turnOutputBytes = 0;
  const result = new Promise((yes, no) => { resolve = yes; reject = no; });
  const close = (reason = new Error('Guest closed')) => {
    worker.terminate();
    controller.abort(reason);
    clearTimeout(timer);
    clearInterval(clockTimer);
    signal?.removeEventListener('abort', abort);
    options.httpBodies?.clear();
    for (const resource of options.gpuRuntime?.buffers?.values() || []) resource.buffer.destroy();
    options.gpuRuntime?.buffers?.clear();
    options.gpuRuntime?.kernels?.clear();
    if (options.gpuDevice) Promise.resolve(options.gpuDevice).then(device => device.destroy(), () => {});
    if (!settled) { settled = true; reject(reason); }
  };
  const abort = () => close(signal.reason || new Error('Guest aborted'));
  const armDeadline = () => { clearTimeout(timer); timer = setTimeout(() => close(new Error(`Guest exceeded ${deadlineMs} ms: ${lastLog.slice(-4000)}`)), deadlineMs); };
  if (signal?.aborted) abort();
  else signal?.addEventListener('abort', abort, {once: true});
  if (!settled) armDeadline();
  worker.onerror = event => close(new Error(event.message));
  worker.onmessage = async ({data: message}) => {
    try {
      if (settled) return;
      if (message.type === 'clock') {
        const timestamp = new BigInt64Array(message.buffer, message.offset, 1);
        const update = () => Atomics.store(timestamp, 0, BigInt(Math.floor(performance.now() * 1000)));
        update(); clockTimer = setInterval(update, 1);
        worker.postMessage({type: 'clock-ready'}); return;
      }
      if (message.type === 'log') { lastLog = message.log; onProgress(message); return; }
      if (message.type === 'ready') { metrics.bootMs = performance.now() - started; onProgress(message); return; }
      if (message.type === 'failed') throw new Error(message.error + '\n' + message.log);
      if (message.type === 'done') {
        if (!message.result.ok) throw new Error(message.result.error + '\n' + message.result.traceback);
        metrics.totalMs = performance.now() - started;
        settled = true; resolve({value: message.result.value, metrics}); close(); return;
      }
      if (message.type !== 'effect') return;
      onProgress({type: 'effect', request: message.request});
      const now = performance.now();
      const beginsTurn = resetLimits?.(message.request) === true;
      if (beginsTurn) {
        turnFrames = turnEffects = turnInputBytes = turnOutputBytes = 0;
        clearTimeout(timer);
      }
      if (lastResponse !== undefined) metrics.guestIntervalsMs.push(now - lastResponse);
      metrics.frames++;
      metrics.effects += message.request.requests?.length || 0;
      metrics.effectBytes += encoder.encode(JSON.stringify(message.request)).length;
      turnFrames++; turnEffects += message.request.requests?.length || 0;
      turnInputBytes += encoder.encode(JSON.stringify(message.request)).length;
      if (turnFrames > 10000 || turnEffects > 10000) throw new Error('Guest effect budget exceeded');
      if (turnInputBytes > options.limitOverrides.maxEffectBytes) throw new Error('Guest effect byte budget exceeded');
      const adapter = leaseAdapter(message.leases);
      metrics.copiedIn += message.leases.reduce((sum, lease) => sum + lease.bytes, 0);
      options.wasmModule = adapter.module;
      const response = await handleBrowserEffects(message.request, options);
      if (settled) return;
      if (beginsTurn) armDeadline();
      metrics.responseBytes += encoder.encode(JSON.stringify(response)).length;
      turnOutputBytes += encoder.encode(JSON.stringify(response)).length;
      if (turnOutputBytes > options.limitOverrides.maxResponseBytes) throw new Error('Guest response byte budget exceeded');
      const writes = adapter.writes();
      metrics.copiedOut += writes.reduce((sum, write) => sum + write.data.byteLength, 0);
      metrics.hostEffectMs.push(performance.now() - now);
      if (metrics.hostEffectMs.length > 10000) metrics.hostEffectMs.shift();
      if (metrics.guestIntervalsMs.length > 10000) metrics.guestIntervalsMs.shift();
      lastResponse = performance.now();
      worker.postMessage({type: 'response', sequence: message.sequence, response, writes, released: adapter.released()},
        writes.map(write => write.data));
    } catch (error) { close(error); }
  };
  if (!settled) worker.postMessage({type: 'boot', appUrl: new URL(appUrl, import.meta.url).href, config});
  return {result, close, metrics};
}
