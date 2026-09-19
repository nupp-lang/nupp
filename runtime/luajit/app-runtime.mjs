import {createKernels} from './aot.mjs';
import {assetsFor} from './assets.mjs';
import {nativeInitialization} from './native.mjs';
import {createWorkerPool} from '../wasm/worker-pool.mjs';
import {createGuest} from './host.mjs';
import {createTransfers} from './transfers.mjs';
import {handleBrowserEffects} from '../wasm/app-runtime.mjs';
const encoder = new TextEncoder();
const defaults = {maxEffects: 256, maxEffectBytes: 4 * 1024 * 1024,
  maxResponseBytes: 8 * 1024 * 1024, maxStorageValueBytes: 1024 * 1024, deadlineMs: 30000};

export function applicationPayload(app, initialize = new Uint8Array()) {
  if (!(app instanceof Uint8Array) || !(initialize instanceof Uint8Array)) throw new Error('Application input must be bytes');
  if (12 + app.length + initialize.length > 7 * 1024 * 1024) throw new Error('Application input exceeds seven MiB');
  const bytes = new Uint8Array(12 + app.length + initialize.length);
  bytes.set(encoder.encode('NUAPP001'));
  new DataView(bytes.buffer).setUint32(8, initialize.length, true);
  bytes.set(initialize, 12); bytes.set(app, 12 + initialize.length);
  return bytes;
}

export async function runNuppLuaJITApp({manifestUrl, app, initialize, managed = false,
  signal, limits: overrides, onProgress, resetLimits, workerEntry, workerSetup, ...services}) {
  const limits = {...defaults, ...overrides};
  for (const [key, value] of Object.entries(limits)) {
    if (!Number.isSafeInteger(value) || value < 1) throw new Error(`Invalid application limit ${key}`);
  }
  const controller = new AbortController();
  const abort = () => controller.abort(signal.reason);
  if (signal?.aborted) abort(); else signal?.addEventListener('abort', abort, {once: true});
  let timer, effectCount = 0, effectBytes = 0, responseBytes = 0;
  const arm = () => {
    clearTimeout(timer);
    timer = setTimeout(() => controller.abort(new Error(`browser application exceeded its ${limits.deadlineMs} ms deadline`)), limits.deadlineMs);
  };
  const options = {...services, limits, signal: controller.signal};
  const guest = createGuest({manifestUrl, app: applicationPayload(app, initialize), signal: controller.signal,
    config: {mode: 'application', managed, workerEntry, workerSetup}, deadlineMs: 30000,
    onProgress(message) { if (message.type === 'ready') arm(); onProgress?.(message); }});
  const aborted = new Promise((_, reject) => {
    const failed = () => reject(controller.signal.reason || new Error('Application cancelled'));
    if (controller.signal.aborted) failed(); else controller.signal.addEventListener('abort', failed, {once: true});
  });
  // The cancellation promise can fire while guest.receive owns the active wait.
  aborted.catch(() => {});
  try {
    while (true) {
      const frame = await guest.receive();
      if (frame.type === 'done') {
        if (!frame.result.ok) throw new Error(frame.result.error);
        const value = frame.result.value;
        if (typeof value === 'string') {
          if (encoder.encode(value).length > limits.maxResponseBytes) throw new Error('Application result exceeds its byte limit');
          return value === '' ? null : JSON.parse(value);
        }
        return value ?? null;
      }
      if (frame.type !== 'effect') throw new Error('Unexpected application frame');
      const request = frame.result;
      const beginsTurn = resetLimits?.(request) === true;
      if (beginsTurn) {
        effectCount = effectBytes = responseBytes = 0;
        clearTimeout(timer);
      }
      effectCount += Array.isArray(request.requests) ? request.requests.length : 0;
      effectBytes += encoder.encode(JSON.stringify(request)).length + (frame.payload?.byteLength || 0);
      if (effectCount > limits.maxEffects || effectBytes > limits.maxEffectBytes) throw new Error('Application effect budget exceeded');
      const transfers = createTransfers(request._leases, frame.payload);
      delete request._leases;
      options.transfers = transfers;
      const response = await Promise.race([(services.effects || handleBrowserEffects)(request, options), aborted]);
      if (beginsTurn) arm();
      const returned = transfers.response();
      response._leases = returned.leases;
      responseBytes += encoder.encode(JSON.stringify(response)).length + returned.payload.length;
      if (responseBytes > limits.maxResponseBytes) throw new Error('Application response budget exceeded');
      guest.respond(response, returned.payload);
    }
  } finally {
    clearTimeout(timer);
    controller.abort(new Error('Application closed'));
    guest.close();
    options.httpBodies?.clear();
    for (const resource of options.gpuRuntime?.buffers?.values() || []) resource.buffer?.destroy();
    if (options.gpuDevice) Promise.resolve(options.gpuDevice).then(device => device.destroy()).catch(() => {});
    signal?.removeEventListener('abort', abort);
  }
}

export async function runPackagedNuppLuaJITApp(manifestUrl, options = {}) {
  const address = new URL(manifestUrl, globalThis.location?.href);
  const response = await fetch(address);
  if (!response.ok) throw new Error(`Cannot fetch application manifest: ${response.status}`);
  const manifest = await response.json();
  if (manifest.schema !== 1 || manifest.runtime !== 'luajit-v86') throw new Error('Unsupported LuaJIT application manifest');
  const base = new URL('.', address);
  const verified = assetsFor(manifest, base);
  const app = await verified(manifest.app);
  const guestBytes = await verified(manifest.guest);
  const guest = JSON.parse(new TextDecoder().decode(guestBytes));
  if (guest.buildKey !== manifest.guestBuildKey) throw new Error('Application guest identity mismatch');
  const kernels = await createKernels(manifest.kernels, verified);
  const native = await nativeInitialization(manifest.nativeLibraries, verified);
  const supplied = options.initialize || new Uint8Array();
  if (!(supplied instanceof Uint8Array)) throw new Error('Application initialization must be bytes');
  const initialize = new Uint8Array(native.length + supplied.length);
  initialize.set(native); initialize.set(supplied, native.length);
  let pool;
  try {
    if (manifest.workers && options.workers !== false) {
      await verified(manifest.workers.lane);
      pool = createWorkerPool({laneUrl: new URL(manifest.workers.lane, base).href,
        manifestUrl: address.href, maxLanes: manifest.workers.maxLanes || 2,
        limits: options.limits || manifest.limits});
    }
    return await runNuppLuaJITApp({...options, app, initialize,
      manifestUrl: new URL(manifest.guest, base).href,
      limits: options.limits || manifest.limits,
      storageName: options.storageName || `nupp-${manifest.assets[manifest.app].sha256.slice(0,24)}`,
      effectHandlers: {...options.effectHandlers, aot: kernels, ...(pool ? {workers: effect => pool.perform(effect)} : {})}});
  } finally { pool?.close(); }
}
