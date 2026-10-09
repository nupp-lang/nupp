import {createKernels} from './aot.mjs';
import {assetsFor, sha256} from './assets.mjs';
import {nativeInitialization} from './native.mjs';
import {createWorkerPool} from '../wasm/worker-pool.mjs';
import {createGuest} from './host.mjs';
import {createTransfers} from './transfers.mjs';
import {closeHostChannel, handleBrowserEffects} from '../wasm/app-runtime.mjs';
const encoder = new TextEncoder();
// A turn is one guest frame round trip on a page, and one task on a worker lane:
// the effects a frame carries, the bytes it and its response move, and the guest
// compute between a response and its next frame. `perRun` bounds the whole run
// and is unbounded unless a caller names a limit, which the playground does.
const LIMIT_KEYS = {
  perTurn: ['maxEffects', 'maxEffectBytes', 'maxResponseBytes', 'computeMs'],
  perRun: ['maxEffects', 'maxEffectBytes', 'maxResponseBytes', 'deadlineMs'],
};
const defaults = {perTurn: {maxEffects: 256, maxEffectBytes: 4 * 1024 * 1024,
  maxResponseBytes: 8 * 1024 * 1024, computeMs: 30000}, perRun: {}};

// Layers limit tables over the defaults, later layers winning key by key.
export function resolveLimits(...layers) {
  const limits = {perTurn: {...defaults.perTurn}, perRun: {...defaults.perRun}};
  for (const layer of layers) {
    if (layer === undefined || layer === null) continue;
    if (typeof layer !== 'object' || Array.isArray(layer)) throw new Error('Application limits must be an object');
    for (const [scope, values] of Object.entries(layer)) {
      const known = LIMIT_KEYS[scope];
      if (!known) throw new Error(`Unknown application limit ${scope}; limits take perTurn and perRun`);
      if (values === undefined) continue;
      if (typeof values !== 'object' || values === null || Array.isArray(values)) throw new Error(`Application limits.${scope} must be an object`);
      for (const [key, value] of Object.entries(values)) {
        if (!known.includes(key)) throw new Error(`Unknown application limit ${scope}.${key}`);
        if (!Number.isSafeInteger(value) || value < 1) throw new Error(`Invalid application limit ${scope}.${key}`);
        limits[scope][key] = value;
      }
    }
  }
  return limits;
}

const exceededMessage = (path, value) => `browser application exceeded limits.${path} (${value})`;
const exceeded = (path, value) => new Error(exceededMessage(path, value));

export function applicationPayload(app, initialize = new Uint8Array()) {
  if (!(app instanceof Uint8Array) || !(initialize instanceof Uint8Array)) throw new Error('Application input must be bytes');
  if (12 + app.length + initialize.length > 7 * 1024 * 1024) throw new Error('Application input exceeds seven MiB');
  const bytes = new Uint8Array(12 + app.length + initialize.length);
  bytes.set(encoder.encode('NUAPP001'));
  new DataView(bytes.buffer).setUint32(8, initialize.length, true);
  bytes.set(initialize, 12); bytes.set(app, 12 + initialize.length);
  return bytes;
}

// Every frame begins a turn unless `beginsTurn` says otherwise, which is how a
// worker lane makes one task its turn. The per-turn compute watchdog is the guest
// host's request deadline, so a spinning guest is terminated rather than awaited.
export async function runNuppLuaJITApp({manifestUrl, app, initialize, managed = false,
  signal, limits: overrides, onProgress, beginsTurn = () => true, workerEntry, workerSetup,
  createGuest: openGuest = createGuest, ...services}) {
  const {perTurn, perRun} = resolveLimits(overrides);
  const controller = new AbortController();
  const abort = () => controller.abort(signal.reason);
  if (signal?.aborted) abort(); else signal?.addEventListener('abort', abort, {once: true});
  let timer;
  const turn = {maxEffects: 0, maxEffectBytes: 0, maxResponseBytes: 0};
  const run = {...turn};
  const count = (limit, amount) => {
    turn[limit] += amount; run[limit] += amount;
    if (turn[limit] > perTurn[limit]) throw exceeded(`perTurn.${limit}`, perTurn[limit]);
    if (perRun[limit] !== undefined && run[limit] > perRun[limit]) throw exceeded(`perRun.${limit}`, perRun[limit]);
  };
  const armRun = () => {
    if (perRun.deadlineMs === undefined) return;
    timer = setTimeout(() => controller.abort(exceeded('perRun.deadlineMs', `${perRun.deadlineMs} ms`)), perRun.deadlineMs);
  };
  // Handlers read the per-turn table: an HTTP body or response is bounded by what
  // one turn may move.
  const options = {...services, limits: perTurn, signal: controller.signal};
  const guest = openGuest({manifestUrl, app: applicationPayload(app, initialize), signal: controller.signal,
    config: {mode: 'application', managed, workerEntry, workerSetup}, deadlineMs: perTurn.computeMs,
    timeoutMessage: exceededMessage('perTurn.computeMs', `${perTurn.computeMs} ms`),
    onProgress(message) { if (message.type === 'ready') armRun(); onProgress?.(message); }});
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
          if (encoder.encode(value).length > perTurn.maxResponseBytes) throw exceeded('perTurn.maxResponseBytes', perTurn.maxResponseBytes);
          return value === '' ? null : JSON.parse(value);
        }
        return value ?? null;
      }
      if (frame.type !== 'effect') throw new Error('Unexpected application frame');
      const request = frame.result;
      if (beginsTurn(request) === true) turn.maxEffects = turn.maxEffectBytes = turn.maxResponseBytes = 0;
      count('maxEffects', Array.isArray(request.requests) ? request.requests.length : 0);
      count('maxEffectBytes', encoder.encode(JSON.stringify(request)).length + (frame.payload?.byteLength || 0));
      const transfers = createTransfers(request._leases, frame.payload);
      delete request._leases;
      options.transfers = transfers;
      const response = await Promise.race([(services.effects || handleBrowserEffects)(request, options), aborted]);
      const returned = transfers.response();
      response._leases = returned.leases;
      count('maxResponseBytes', encoder.encode(JSON.stringify(response)).length + returned.payload.length);
      guest.respond(response, returned.payload);
    }
  } finally {
    clearTimeout(timer);
    controller.abort(new Error('Application closed'));
    guest.close();
    // The session is over: the page releases what the application never took.
    closeHostChannel(options);
    options.httpBodies?.clear();
    for (const file of options.files?.handles?.values() || []) {
      try { file.access.close(); } catch {}
    }
    options.files?.handles?.clear();
    for (const resource of options.gpuRuntime?.buffers?.values() || []) resource.buffer?.destroy();
    if (options.gpuDevice) Promise.resolve(options.gpuDevice).then(device => device.destroy()).catch(() => {});
    signal?.removeEventListener('abort', abort);
  }
}

// The handlers a packaged application adds to the caller's. With a worker pool, the
// parallelism a caller can use is the pool's lane count rather than the browser's
// core estimate, unless the caller answers `system` itself.
export function packagedEffectHandlers(supplied, kernels, pool) {
  if (!pool) return {...supplied, aot: kernels};
  return {system: () => ({availableParallelism: pool.lanes}), ...supplied, aot: kernels,
    workers: effect => pool.perform(effect)};
}

// A worker lane refetches the manifest by URL, so it is booted with the SHA-256 of
// the one its page verified: a deploy between page load and lane start would
// otherwise pair two builds, whose worker frames need not agree.
export async function runPackagedNuppLuaJITApp(manifestUrl, {manifestDigest, ...options} = {}) {
  const address = new URL(manifestUrl, globalThis.location?.href);
  const response = await fetch(address);
  if (!response.ok) throw new Error(`Cannot fetch application manifest: ${response.status}`);
  const manifestBytes = new Uint8Array(await response.arrayBuffer());
  const digest = await sha256(manifestBytes);
  if (manifestDigest !== undefined && digest !== manifestDigest) {
    throw new Error('the application manifest changed after the page loaded it; reload the page');
  }
  const manifest = JSON.parse(new TextDecoder().decode(manifestBytes));
  if (manifest.schema !== 1 || manifest.runtime !== 'luajit-v86') throw new Error('Unsupported LuaJIT application manifest');
  const limits = resolveLimits(manifest.limits, options.limits);
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
        manifestUrl: address.href, manifestDigest: digest, maxLanes: manifest.workers.maxLanes || 2, limits,
        requestPersistentStorage: options.requestPersistentStorage});
    }
    return await runNuppLuaJITApp({...options, app, initialize,
      manifestUrl: new URL(manifest.guest, base).href, limits,
      storageName: options.storageName || `nupp-${manifest.assets[manifest.app].sha256.slice(0,24)}`,
      requestPersistentStorage: options.requestPersistentStorage,
      effectHandlers: packagedEffectHandlers(options.effectHandlers, kernels, pool)});
  } finally { pool?.close(); }
}
