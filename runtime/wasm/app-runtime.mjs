import { createWorkerPool } from "./worker-pool.mjs";

function hostError(module) {
  const pointer = module._nupp_app_last_error();
  return pointer ? module.UTF8ToString(pointer) : "unknown Nupp Wasm app error";
}

const APP_SUSPENDED = 1;
const APP_COMPLETE = 2;
const APP_FAILED = 3;
const APP_CANCELLED = 4;
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder("utf-8", {fatal: true});
const DEFAULT_LIMITS = Object.freeze({
  maxEffects: 256,
  maxEffectBytes: 4 * 1024 * 1024,
  maxResponseBytes: 8 * 1024 * 1024,
  maxStorageValueBytes: 1024 * 1024,
  deadlineMs: 30_000,
});

function payload(module) {
  const length = module._nupp_app_payload_size();
  const pointer = module._nupp_app_payload_data();
  if (length === 0) return "";
  if (!pointer) throw new Error("the Nupp app host exposed a null payload");
  return textDecoder.decode(module.HEAPU8.slice(pointer, pointer + length));
}

function callWithBytes(module, fn, bytes) {
  const pointer = module._malloc(bytes.length || 1);
  if (!pointer) throw new Error("cannot allocate the Nupp app protocol buffer");
  try {
    module.HEAPU8.set(bytes, pointer);
    return fn(pointer, bytes.length);
  } finally {
    module._free(pointer);
  }
}

function bytesToBase64(bytes) {
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

function base64ToBytes(text, label) {
  if (typeof text !== "string" || text.length % 4 !== 0 ||
      !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(text)) {
    throw new Error(`${label} must be canonical base64`);
  }
  return Uint8Array.from(atob(text), (character) => character.charCodeAt(0));
}

function webCrypto(options) {
  const selected = options.crypto || globalThis.crypto;
  if (!selected?.getRandomValues || !selected?.subtle) {
    throw new Error("Web Crypto is unavailable in this host");
  }
  return selected;
}

function checkedLimits(overrides = {}) {
  const limits = {...DEFAULT_LIMITS};
  for (const name of Object.keys(limits)) {
    if (overrides[name] === undefined) continue;
    if (!Number.isInteger(overrides[name]) || overrides[name] < 1) {
      throw new Error(`browser application limit ${name} must be a positive integer`);
    }
    limits[name] = overrides[name];
  }
  return limits;
}

function abortError(signal) {
  return signal?.reason || new DOMException("The operation was aborted", "AbortError");
}

function abortable(value, signal) {
  if (!signal) return value;
  if (signal.aborted) return Promise.reject(abortError(signal));
  return new Promise((resolve, reject) => {
    const abort = () => reject(abortError(signal));
    signal.addEventListener("abort", abort, {once: true});
    Promise.resolve(value).then(
      (result) => {
        signal.removeEventListener("abort", abort);
        resolve(result);
      },
      (error) => {
        signal.removeEventListener("abort", abort);
        reject(error);
      },
    );
  });
}

async function performTimeEffect(effect, options) {
  if (effect.operation === "now") return (options.performance || globalThis.performance).now();
  if (effect.operation === "wall") return (options.dateNow || Date.now)();
  if (effect.operation !== "sleep" || typeof effect.milliseconds !== "number" ||
      !Number.isFinite(effect.milliseconds) || effect.milliseconds < 0) {
    throw new Error("invalid browser time operation");
  }
  await new Promise((resolve, reject) => {
    if (options.signal?.aborted) {
      reject(abortError(options.signal));
      return;
    }
    const finish = () => {
      options.signal?.removeEventListener("abort", cancel);
      resolve();
    };
    const timer = setTimeout(finish, effect.milliseconds);
    const cancel = () => {
      clearTimeout(timer);
      reject(abortError(options.signal));
    };
    options.signal?.addEventListener("abort", cancel, {once: true});
  });
  return null;
}

async function performRandomEffect(effect, options) {
  if (!Number.isInteger(effect.count) || effect.count < 0 || effect.count > 1024 * 1024) {
    throw new Error("browser random byte count must be between 0 and 1048576");
  }
  const selected = webCrypto(options);
  const bytes = new Uint8Array(effect.count);
  for (let at = 0; at < bytes.length; at += 65536) {
    selected.getRandomValues(bytes.subarray(at, Math.min(at + 65536, bytes.length)));
  }
  return {
    bytesBase64: bytesToBase64(bytes),
    ...(effect.wallTime ? {wallTimeMs: (options.dateNow || Date.now)()} : {}),
  };
}

function hex(bytes) {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function performSha256Effect(effect, options) {
  const bytes = base64ToBytes(effect.bytesBase64, "SHA-256 input");
  const digest = await webCrypto(options).subtle.digest("SHA-256", bytes);
  return hex(new Uint8Array(digest));
}

async function performHmacEffect(effect, options) {
  const selected = webCrypto(options);
  const keyBytes = base64ToBytes(effect.keyBase64, "HMAC key");
  const message = base64ToBytes(effect.messageBase64, "HMAC message");
  const key = await selected.subtle.importKey(
    "raw", keyBytes, {name: "HMAC", hash: "SHA-256"}, false, ["sign"],
  );
  const digest = new Uint8Array(await selected.subtle.sign("HMAC", key, message));
  return {digestBase64: bytesToBase64(digest)};
}

const XOR_U32_WGSL = `
struct Uniforms {
  count: u32,
  mask: u32,
}

@group(0) @binding(0) var<storage, read> input: array<u32>;
@group(0) @binding(1) var<storage, read_write> output: array<u32>;
@group(0) @binding(2) var<uniform> uniforms: Uniforms;

@compute @workgroup_size(64)
fn xor_u32(@builtin(global_invocation_id) id: vec3<u32>) {
  if (id.x < uniforms.count) {
    output[id.x] = input[id.x] ^ uniforms.mask;
  }
}
`;

function webGpu(options) {
  const gpu = options.gpu || globalThis.navigator?.gpu;
  if (!gpu?.requestAdapter) throw new Error("WebGPU is unavailable in this Worker");
  return gpu;
}

function webGpuUsage(options) {
  const usage = options.GPUBufferUsage || globalThis.GPUBufferUsage;
  if (!usage) throw new Error("WebGPU buffer usage constants are unavailable");
  return usage;
}

function webGpuMapMode(options) {
  const mode = options.GPUMapMode || globalThis.GPUMapMode;
  if (!mode) throw new Error("WebGPU map mode constants are unavailable");
  return mode;
}

function uint32(value, name) {
  if (!Number.isInteger(value) || value < 0 || value > 0xffffffff) {
    throw new Error(`browser GPU ${name} must be a uint32`);
  }
  return value >>> 0;
}

async function gpuDevice(options) {
  if (!options.gpuDevice) {
    options.gpuDevice = (async () => {
      const adapter = await webGpu(options).requestAdapter();
      if (!adapter) throw new Error("no WebGPU adapter is available");
      const device = await adapter.requestDevice();
      device.lost?.then((info) => {
        options.gpuDevice = null;
        options.gpuPipeline = null;
        options.gpuFailure = `WebGPU device was lost: ${info?.message || info?.reason || "unknown reason"}`;
      });
      return device;
    })();
  }
  return options.gpuDevice;
}

async function gpuPipeline(device, options) {
  if (!options.gpuPipeline) {
    const descriptor = {
      layout: "auto",
      compute: {module: device.createShaderModule({code: XOR_U32_WGSL}), entryPoint: "xor_u32"},
    };
    options.gpuPipeline = device.createComputePipelineAsync
      ? device.createComputePipelineAsync(descriptor)
      : Promise.resolve(device.createComputePipeline(descriptor));
  }
  return options.gpuPipeline;
}

function gpuRuntime(options) {
  return options.gpuRuntime ||= {buffers: new Map(), kernels: new Map(), nextBuffer: 1, nextKernel: 1};
}

function gpuLease(effect, options, expectedBytes) {
  const module = options.wasmModule;
  const id = effect.lease;
  if (!module || !Number.isInteger(id) || id < 1 || !module._nupp_wasm_lease_address ||
      !module._nupp_wasm_lease_size || !module._nupp_wasm_release_lease) {
    throw new Error("browser GPU operation has no valid Wasm transfer lease");
  }
  const pointer = module._nupp_wasm_lease_address(id);
  const bytes = module._nupp_wasm_lease_size(id);
  if (!pointer || !bytes || (expectedBytes !== undefined && bytes !== expectedBytes)) {
    throw new Error("browser GPU transfer lease is stale or has the wrong size");
  }
  if (!Number.isInteger(pointer) || pointer < 0 || !Number.isInteger(bytes) || bytes < 0 ||
      !module.HEAPU8 || pointer > module.HEAPU8.byteLength || bytes > module.HEAPU8.byteLength - pointer) {
    throw new Error("browser GPU transfer lease is outside Wasm memory");
  }
  return {id, bytes, view: module.HEAPU8.subarray(pointer, pointer + bytes), module};
}

// Releases the lease an effect names, whether or not gpuLease returned it:
// the Lua side only releases after a successful answer, so every failed
// operation would otherwise strand one of the fixed lease slots.
function releaseEffectLease(effect, options) {
  const module = options.wasmModule;
  const id = effect.lease;
  if (module && module._nupp_wasm_release_lease && Number.isInteger(id) && id > 0) {
    module._nupp_wasm_release_lease(id);
  }
}

function gpuBuffer(runtime, id) {
  const resource = runtime.buffers.get(id);
  if (!resource) throw new Error("browser GPU buffer handle is unknown");
  return resource;
}

async function performGpuRuntimeEffect(effect, options) {
  try {
    return await performGpuOperation(effect, options);
  } finally {
    if (GPU_LEASE_OPERATIONS.has(effect.operation)) releaseEffectLease(effect, options);
  }
}

const GPU_LEASE_OPERATIONS = new Set(["runtime-upload", "runtime-dispatch", "runtime-download"]);

async function performGpuOperation(effect, options) {
  const usage = webGpuUsage(options);
  const device = await gpuDevice(options);
  if (options.gpuFailure) throw new Error(options.gpuFailure);
  const runtime = gpuRuntime(options);
  if (effect.operation === "runtime-open") return {driver: "webgpu"};
  if (effect.operation === "runtime-create-buffer") {
    const bytes = uint32(effect.bytes, "buffer byte length");
    if (bytes === 0 || bytes % 4 !== 0) throw new Error("browser GPU buffers need a positive four-byte size");
    const id = runtime.nextBuffer++;
    runtime.buffers.set(id, {
      bytes,
      buffer: device.createBuffer({size: bytes, usage: usage.STORAGE | usage.COPY_DST | usage.COPY_SRC}),
    });
    return {buffer: id};
  }
  if (effect.operation === "runtime-destroy-buffer") {
    const resource = gpuBuffer(runtime, uint32(effect.buffer, "buffer handle"));
    resource.buffer.destroy();
    runtime.buffers.delete(effect.buffer);
    return null;
  }
  if (effect.operation === "runtime-compile") {
    if (typeof effect.wgsl !== "string" || effect.wgsl.length === 0 ||
        typeof effect.entrypoint !== "string" || effect.entrypoint.length === 0 ||
        !Number.isInteger(effect.readonly) || effect.readonly < 0 ||
        !Number.isInteger(effect.writable) || effect.writable < 1 ||
        !Number.isInteger(effect.uniformBytes) || effect.uniformBytes < 4 || effect.uniformBytes > 128 ||
        effect.uniformBytes % 4 !== 0 || !Number.isInteger(effect.threads) || effect.threads < 1 || effect.threads > 256) {
      throw new Error("browser GPU kernel descriptor is invalid");
    }
    const descriptor = {
      layout: "auto",
      compute: {module: device.createShaderModule({code: effect.wgsl}), entryPoint: effect.entrypoint},
    };
    const pipeline = device.createComputePipelineAsync
      ? await device.createComputePipelineAsync(descriptor)
      : device.createComputePipeline(descriptor);
    const id = runtime.nextKernel++;
    runtime.kernels.set(id, {pipeline, readonly: effect.readonly, writable: effect.writable,
      uniformBytes: effect.uniformBytes, threads: effect.threads});
    return {kernel: id};
  }
  if (effect.operation === "runtime-destroy-kernel") {
    runtime.kernels.delete(uint32(effect.kernel, "kernel handle"));
    return null;
  }
  if (effect.operation === "runtime-upload") {
    const resource = gpuBuffer(runtime, uint32(effect.buffer, "buffer handle"));
    const lease = gpuLease(effect, options, resource.bytes);
    device.queue.writeBuffer(resource.buffer, 0, lease.view);
    return null;
  }
  if (effect.operation === "runtime-dispatch") {
    const kernel = runtime.kernels.get(uint32(effect.kernel, "kernel handle"));
    if (!kernel || !Array.isArray(effect.read) || !Array.isArray(effect.write)) {
      throw new Error("browser GPU dispatch names an unknown kernel or buffers");
    }
    if (effect.read.length !== kernel.readonly || effect.write.length !== kernel.writable) {
      throw new Error("browser GPU dispatch has the wrong binding count");
    }
    const count = uint32(effect.count, "dispatch count");
    const lease = gpuLease(effect, options, kernel.uniformBytes);
    const entries = [];
    let binding = 0;
    for (const id of effect.read) entries.push({binding: binding++, resource: {buffer: gpuBuffer(runtime, uint32(id, "read buffer")).buffer}});
    for (const id of effect.write) entries.push({binding: binding++, resource: {buffer: gpuBuffer(runtime, uint32(id, "write buffer")).buffer}});
    const uniform = device.createBuffer({size: kernel.uniformBytes, usage: usage.UNIFORM | usage.COPY_DST});
    try {
      device.queue.writeBuffer(uniform, 0, lease.view);
      entries.push({binding, resource: {buffer: uniform}});
      const bindGroup = device.createBindGroup({layout: kernel.pipeline.getBindGroupLayout(0), entries});
      const encoder = device.createCommandEncoder();
      const pass = encoder.beginComputePass();
      pass.setPipeline(kernel.pipeline);
      pass.setBindGroup(0, bindGroup);
      pass.dispatchWorkgroups(Math.ceil(count / kernel.threads));
      pass.end();
      device.queue.submit([encoder.finish()]);
    } finally {
      uniform.destroy();
    }
    return null;
  }
  if (effect.operation === "runtime-download") {
    let readback;
    try {
      const resource = gpuBuffer(runtime, uint32(effect.buffer, "buffer handle"));
      gpuLease(effect, options, resource.bytes);
      readback = device.createBuffer({size: resource.bytes, usage: usage.MAP_READ | usage.COPY_DST});
      const encoder = device.createCommandEncoder();
      encoder.copyBufferToBuffer(resource.buffer, 0, readback, 0, resource.bytes);
      device.queue.submit([encoder.finish()]);
      await readback.mapAsync(webGpuMapMode(options).READ);
      // Mapping yields to the host. Memory may grow or the lease may be revoked
      // before it completes, so project a fresh checked view at the actual write.
      gpuLease(effect, options, resource.bytes).view.set(new Uint8Array(readback.getMappedRange()));
      readback.unmap();
      return null;
    } finally {
      if (readback) readback.destroy();
    }
  }
  if (effect.operation === "runtime-synchronize") {
    if (device.queue.onSubmittedWorkDone) await device.queue.onSubmittedWorkDone();
    return null;
  }
  throw new Error("unsupported browser GPU runtime operation");
}

async function performGpuEffect(effect, options) {
  if (typeof effect.operation === "string" && effect.operation.startsWith("runtime-")) {
    return performGpuRuntimeEffect(effect, options);
  }
  if (effect.operation !== "xor-u32") throw new Error("unsupported browser GPU operation");
  if (!Array.isArray(effect.values) || effect.values.length < 1 || effect.values.length > 262144) {
    throw new Error("browser GPU xor needs 1 through 262144 uint32 values");
  }
  if (options.signal?.aborted) throw abortError(options.signal);
  const values = Uint32Array.from(effect.values, (value) => uint32(value, "input"));
  const mask = uint32(effect.mask, "mask");
  const bytes = values.byteLength;
  const usage = webGpuUsage(options);
  const device = await gpuDevice(options);
  if (options.gpuFailure) throw new Error(options.gpuFailure);
  const pipeline = await gpuPipeline(device, options);
  const input = device.createBuffer({size: bytes, usage: usage.STORAGE | usage.COPY_DST});
  const output = device.createBuffer({size: bytes, usage: usage.STORAGE | usage.COPY_SRC});
  const uniform = device.createBuffer({size: 8, usage: usage.UNIFORM | usage.COPY_DST});
  const readback = device.createBuffer({size: bytes, usage: usage.MAP_READ | usage.COPY_DST});
  try {
    device.queue.writeBuffer(input, 0, values);
    device.queue.writeBuffer(uniform, 0, Uint32Array.of(values.length, mask));
    const bindGroup = device.createBindGroup({
      layout: pipeline.getBindGroupLayout(0),
      entries: [
        {binding: 0, resource: {buffer: input}},
        {binding: 1, resource: {buffer: output}},
        {binding: 2, resource: {buffer: uniform}},
      ],
    });
    const encoder = device.createCommandEncoder();
    const pass = encoder.beginComputePass();
    pass.setPipeline(pipeline);
    pass.setBindGroup(0, bindGroup);
    pass.dispatchWorkgroups(Math.ceil(values.length / 64));
    pass.end();
    encoder.copyBufferToBuffer(output, 0, readback, 0, bytes);
    device.queue.submit([encoder.finish()]);
    await readback.mapAsync(webGpuMapMode(options).READ);
    const result = Array.from(new Uint32Array(readback.getMappedRange().slice(0)));
    readback.unmap();
    return {values: result};
  } finally {
    input.destroy();
    output.destroy();
    uniform.destroy();
    readback.destroy();
  }
}

function openStorage(name, indexedDB = globalThis.indexedDB) {
  if (!indexedDB) throw new Error("IndexedDB is unavailable in this Worker");
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(name, 1);
    request.onupgradeneeded = () => request.result.createObjectStore("values");
    request.onerror = () => reject(request.error || new Error("cannot open browser storage"));
    request.onsuccess = () => resolve(request.result);
  });
}

function idbRequest(request) {
  return new Promise((resolve, reject) => {
    request.onerror = () => reject(request.error || new Error("browser storage request failed"));
    request.onsuccess = () => resolve(request.result);
  });
}

async function defaultStorage(options) {
  if (!options.storagePromise) {
    options.storagePromise = openStorage(
      options.storageName || "nupp-browser-application", options.indexedDB,
    );
  }
  const database = await options.storagePromise;
  return {
    async get(key) {
      const value = await idbRequest(database.transaction("values").objectStore("values").get(key));
      return value === undefined ? undefined : String(value);
    },
    async set(key, value) {
      await idbRequest(database.transaction("values", "readwrite").objectStore("values").put(value, key));
    },
    async remove(key) {
      await idbRequest(database.transaction("values", "readwrite").objectStore("values").delete(key));
    },
    async clear() {
      await idbRequest(database.transaction("values", "readwrite").objectStore("values").clear());
    },
  };
}

async function performStorageEffect(effect, options) {
  const storage = options.storage || await defaultStorage(options);
  // A cancelled run was told its turn never completed, so it must stop
  // committing. Best-effort: an abort landing mid-transaction still lands,
  // but one that already happened does not go on writing.
  if (options.signal?.aborted) {
    throw options.signal.reason || new DOMException("The operation was aborted", "AbortError");
  }
  if (effect.operation === "clear") {
    await storage.clear();
    return null;
  }
  if (typeof effect.key !== "string" || effect.key.length === 0 ||
      textEncoder.encode(effect.key).length > 1024) {
    throw new Error("browser storage keys must contain 1 through 1024 UTF-8 bytes");
  }
  if (effect.operation === "get") {
    const value = await storage.get(effect.key);
    return value === undefined || value === null ? {found: false} : {found: true, value: String(value)};
  }
  if (effect.operation === "remove") {
    await storage.remove(effect.key);
    return null;
  }
  if (effect.operation === "set" && typeof effect.value === "string") {
    if (textEncoder.encode(effect.value).length > options.limits.maxStorageValueBytes) {
      throw new Error(`browser storage value exceeded ${options.limits.maxStorageValueBytes} bytes`);
    }
    await storage.set(effect.key, effect.value);
    return null;
  }
  throw new Error("invalid browser storage operation");
}

async function performHttpEffect(effect, options) {
  if (typeof effect.url !== "string" || !/^https?:\/\//i.test(effect.url)) {
    throw new Error("browser HTTP effects require an absolute http or https URL");
  }
  const controller = new AbortController();
  const abort = () => controller.abort(options.signal?.reason);
  options.signal?.addEventListener("abort", abort, {once: true});
  const timeout = Number.isInteger(effect.timeoutMs) && effect.timeoutMs > 0
    ? setTimeout(() => controller.abort(new Error("HTTP request timed out")), effect.timeoutMs)
    : undefined;
  try {
    const headers = new Headers();
    for (const pair of effect.headers || []) {
      if (!Array.isArray(pair) || pair.length !== 2) throw new Error("invalid browser HTTP header");
      headers.append(pair[0], pair[1]);
    }
    const body = effect.bodyBase64 === undefined
      ? undefined
      : base64ToBytes(effect.bodyBase64, "HTTP request body");
    const response = await (options.fetch || globalThis.fetch)(effect.url, {
      method: effect.method || "GET",
      headers,
      body,
      redirect: "follow",
      signal: controller.signal,
    });
    const protocolLimit = Math.floor(options.limits.maxResponseBytes * 3 / 4);
    const maxBytes = Number.isInteger(effect.maxBytes) && effect.maxBytes > 0
      ? Math.min(effect.maxBytes, protocolLimit)
      : protocolLimit;
    const declared = Number(response.headers.get("content-length"));
    if (Number.isFinite(declared) && declared > maxBytes) {
      throw new Error(`HTTP response exceeded maxBytes (${maxBytes})`);
    }
    const chunks = [];
    let length = 0;
    if (response.body?.getReader) {
      const reader = response.body.getReader();
      while (true) {
        const {done, value} = await reader.read();
        if (done) break;
        length += value.length;
        if (length > maxBytes) {
          await reader.cancel("Nupp HTTP response limit reached");
          throw new Error(`HTTP response exceeded maxBytes (${maxBytes})`);
        }
        chunks.push(value);
      }
    } else {
      const value = new Uint8Array(await response.arrayBuffer());
      length = value.length;
      if (length > maxBytes) throw new Error(`HTTP response exceeded maxBytes (${maxBytes})`);
      chunks.push(value);
    }
    const bytes = new Uint8Array(length);
    let at = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, at);
      at += chunk.length;
    }
    return {
      status: response.status,
      url: response.url || effect.url,
      headers: Array.from(response.headers.entries()),
      bodyBase64: bytesToBase64(bytes),
    };
  } finally {
    if (timeout !== undefined) clearTimeout(timeout);
    options.signal?.removeEventListener("abort", abort);
  }
}

export async function handleBrowserEffects(message, options = {}) {
  if (message?.kind === "poll") {
    await new Promise((resolve) => setTimeout(resolve, 0));
    return {responses: []};
  }
  if (message?.kind !== "effects" || !Array.isArray(message.requests)) {
    throw new Error("the Nupp app yielded an unknown browser effect message");
  }
  options.limits ||= checkedLimits(options.limitOverrides);
  if (message.requests.length > options.limits.maxEffects) {
    throw new Error(`browser application yielded more than ${options.limits.maxEffects} effects`);
  }
  const responses = await Promise.all(message.requests.map(async (effect) => {
    if (!Number.isInteger(effect?.id) || effect.id < 1) {
      return {id: effect?.id, ok: false, error: "browser effect id is invalid"};
    }
    try {
      let value;
      const supplied = options.effectHandlers?.[effect.kind];
      if (supplied) value = await supplied(effect, options);
      else if (effect.kind === "http") value = await performHttpEffect(effect, options);
      else if (effect.kind === "time") value = await performTimeEffect(effect, options);
      else if (effect.kind === "random") value = await performRandomEffect(effect, options);
      else if (effect.kind === "sha256") value = await performSha256Effect(effect, options);
      else if (effect.kind === "hmac-sha256") value = await performHmacEffect(effect, options);
      else if (effect.kind === "storage") value = await performStorageEffect(effect, options);
      else if (effect.kind === "gpu") value = await performGpuEffect(effect, options);
      else throw new Error(`unsupported browser effect ${effect.kind}`);
      return {id: effect.id, ok: true, value};
    } catch (error) {
      return {id: effect.id, ok: false, error: String(error?.message || error)};
    }
  }));
  return {responses};
}

async function driveApplication(module, source, options) {
  options.limits = checkedLimits(options.limitOverrides);
  options.wasmModule = module;
  const started = performance.now();
  const outerSignal = options.signal;
  const deadline = new AbortController();
  const forwardAbort = () => deadline.abort(outerSignal.reason);
  if (outerSignal?.aborted) forwardAbort();
  else outerSignal?.addEventListener("abort", forwardAbort, {once: true});
  let deadlineTimer = setTimeout(() => deadline.abort(
    new Error(`browser application exceeded its ${options.limits.deadlineMs} ms deadline`),
  ), options.limits.deadlineMs);
  options.signal = deadline.signal;
  let effectCount = 0;
  let effectBytes = 0;
  let responseBytes = 0;
  let turnStarted = started;
  // A worker lane runs the same payload for as long as its pool keeps it, so its
  // budget is per task rather than for one application run. `resetLimits` names
  // the request that begins a turn; without it every count is cumulative, which is
  // what a page's own application wants.
  const stopDeadline = () => clearTimeout(deadlineTimer);
  const armDeadline = (what) => {
    clearTimeout(deadlineTimer);
    deadlineTimer = setTimeout(() => deadline.abort(
      new Error(`browser ${what} exceeded its ${options.limits.deadlineMs} ms deadline`),
    ), options.limits.deadlineMs);
  };
  try {
    let status = callWithBytes(
      module,
      options.managed ? module._nupp_app_start_managed : module._nupp_app_start,
      source,
    );
    while (status === APP_SUSPENDED) {
      if (options.signal?.aborted) {
        module._nupp_app_cancel();
        throw options.signal.reason || new DOMException("The operation was aborted", "AbortError");
      }
      let request;
      let beginsTurn = false;
      try {
        const requestText = payload(module);
        request = JSON.parse(requestText);
        // A turn-beginning frame is the one whose effect waits, unbounded, for
        // the lane's next task. Its counters reset now, and the deadline clock
        // stops until the task is in hand, so an idle lane is not killed for
        // waiting and the wait is never billed to the task that follows it.
        beginsTurn = options.resetLimits?.(request) === true;
        if (beginsTurn) {
          effectCount = 0;
          effectBytes = 0;
          responseBytes = 0;
          turnStarted = performance.now();
          stopDeadline();
        }
        effectBytes += textEncoder.encode(requestText).length;
        if (effectBytes > options.limits.maxEffectBytes) {
          throw new Error(`browser effect payloads exceeded ${options.limits.maxEffectBytes} bytes`);
        }
        if (performance.now() - turnStarted > options.limits.deadlineMs) {
          throw new Error(`browser application exceeded its ${options.limits.deadlineMs} ms deadline`);
        }
        effectCount += Array.isArray(request?.requests) ? request.requests.length : 0;
        if (effectCount > options.limits.maxEffects) {
          throw new Error(`browser application exceeded ${options.limits.maxEffects} effects`);
        }
        const response = await abortable(
          (options.effects || handleBrowserEffects)(request, options), options.signal,
        );
        if (beginsTurn) {
          turnStarted = performance.now();
          armDeadline("worker lane");
        }
        const bytes = textEncoder.encode(JSON.stringify(response));
        responseBytes += bytes.length;
        if (responseBytes > options.limits.maxResponseBytes) {
          throw new Error(`browser effect responses exceeded ${options.limits.maxResponseBytes} bytes`);
        }
        status = callWithBytes(module, module._nupp_app_resume, bytes);
      } catch (error) {
        if (module._nupp_app_status() === APP_SUSPENDED) module._nupp_app_cancel();
        throw error;
      }
    }
    if (status === APP_FAILED) throw new Error(hostError(module));
    if (status === APP_CANCELLED) throw new Error("the Nupp application was cancelled");
    if (status !== APP_COMPLETE) throw new Error(`unknown Nupp app status ${status}`);
    const result = payload(module);
    if (textEncoder.encode(result).length > options.limits.maxResponseBytes) {
      throw new Error(`browser application result exceeded ${options.limits.maxResponseBytes} bytes`);
    }
    if (result === "") return null;
    try {
      return JSON.parse(result);
    } catch (error) {
      throw new Error(`the Nupp app returned invalid structured JSON: ${error.message}`);
    }
  } finally {
    clearTimeout(deadlineTimer);
    outerSignal?.removeEventListener("abort", forwardAbort);
  }
}

function relativeAsset(name, label) {
  if (typeof name !== "string" || name.length === 0 || name.includes("\\")) {
    throw new Error(`${label} must be a nonempty relative asset path`);
  }
  const parts = name.split("/");
  if (name.startsWith("/") || parts.some((part) => part === "" || part === "." || part === "..")) {
    throw new Error(`${label} must stay inside the browser application package`);
  }
  return name;
}

async function digest(bytes) {
  if (!globalThis.crypto?.subtle) {
    throw new Error("Web Crypto SHA-256 is unavailable in this host");
  }
  const answer = await globalThis.crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(answer), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function verifiedAsset(fetchAsset, base, record, label) {
  const file = relativeAsset(record?.file, `${label}.file`);
  if (!/^[0-9a-f]{64}$/.test(record?.sha256 || "")) {
    throw new Error(`${label}.sha256 must be a lowercase SHA-256 digest`);
  }
  const response = await fetchAsset(new URL(file, base));
  if (!response.ok) throw new Error(`cannot fetch ${label}: HTTP ${response.status}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (record.bytes !== undefined && bytes.length !== record.bytes) {
    throw new Error(`${label} has ${bytes.length} bytes; expected ${record.bytes}`);
  }
  const actual = await digest(bytes);
  if (actual !== record.sha256) {
    throw new Error(`${label} SHA-256 mismatch: expected ${record.sha256}, found ${actual}`);
  }
  return bytes;
}

export async function runNuppWasmApp({
  createHost,
  locateFile,
  app,
  sideModules,
  wasmBinary,
  effects,
  effectHandlers,
  resetLimits,
  fetch,
  signal,
  limits,
  storage,
  storageName,
  initialize,
  managed,
}) {
  const module = await createHost({
    locateFile,
    ...(wasmBinary ? { wasmBinary } : {}),
  });
  const state = module._nupp_app_boot();
  if (!state) throw new Error(hostError(module));
  if (initialize) {
    const initialized = callWithBytes(module, module._nupp_app_initialize, initialize);
    if (!initialized) throw new Error(hostError(module));
  }

  const sideStacks = [];
  for (const side of sideModules) {
    const stackSize = side.stackSize || 1024 * 1024;
    const stack = module._malloc(stackSize);
    if (!stack) throw new Error("cannot allocate the Wasm AOT side-module stack");
    sideStacks.push(stack);
    module.nuppSetSideStackPointer(stack + stackSize);
    const scope = {};
    await module.loadDynamicLibrary(side.url, {
      loadAsync: true,
      global: false,
      nodelete: true,
    }, scope);
    const register = scope[side.registrar];
    if (typeof register !== "function") {
      throw new Error(
        "Wasm AOT registrar " + side.registrar + " is missing; loaded " + Object.keys(scope).join(",")
      );
    }
    register(state);
  }

  const source = app instanceof Uint8Array ? app : new Uint8Array(app);
  return driveApplication(module, source, {
    effects, effectHandlers, resetLimits, fetch, signal,
    limitOverrides: limits, storage, storageName, managed,
  });
}

export async function runPackagedNuppWasmApp(manifestUrl, options = {}) {
  const fetchAsset = options.fetch || globalThis.fetch;
  if (typeof fetchAsset !== "function") throw new Error("fetch is unavailable in this host");
  const manifestAddress = new URL(manifestUrl, globalThis.location?.href);
  const response = await fetchAsset(manifestAddress);
  if (!response.ok) throw new Error(`cannot fetch browser application manifest: HTTP ${response.status}`);
  const manifest = await response.json();
  if (manifest.schemaVersion !== 1 || manifest.target !== "wasm32-unknown-emscripten") {
    throw new Error("unsupported Nupp browser application manifest");
  }
  const base = new URL(".", manifestAddress);
  const hostModule = relativeAsset(manifest.runtime?.module?.file, "runtime.module.file");
  if (!/^[0-9a-f]{64}$/.test(manifest.runtime?.module?.sha256 || "") ||
      !hostModule.includes(manifest.runtime.module.sha256.slice(0, 16))) {
    throw new Error("runtime.module must use its content-addressed filename");
  }
  const [app, wasmBinary] = await Promise.all([
    verifiedAsset(fetchAsset, base, manifest.app, "app"),
    verifiedAsset(fetchAsset, base, manifest.runtime.wasm, "runtime.wasm"),
  ]);
  const sideRecords = Array.isArray(manifest.sideModules) ? manifest.sideModules : [];
  const sideBytes = await Promise.all(sideRecords.map((record, index) =>
    verifiedAsset(fetchAsset, base, record, `sideModules[${index}]`)
  ));
  const createHost = (await import(new URL(hostModule, base).href)).default;
  const objectUrls = [];
  let pool;
  try {
    const sideModules = sideRecords.map((record, index) => {
      if (typeof record.registrar !== "string" || !/^nupp_wasm_register_[a-z0-9]+$/.test(record.registrar)) {
        throw new Error(`sideModules[${index}].registrar is invalid`);
      }
      const url = URL.createObjectURL(new Blob([sideBytes[index]], {type: "application/wasm"}));
      objectUrls.push(url);
      return {url, registrar: record.registrar, stackSize: record.stackSize};
    });
    // A page whose application reached worker tasks gets a bounded pool of lanes,
    // each booting this same verified manifest in its own Worker. The pool is the
    // page's, not one scope's, so it outlives every scope and closes with the run.
    if (manifest.workers && options.workers !== false) {
      // The lane is executable and gets the same verification as every other
      // asset; a stale or swapped worker-lane.mjs beside a verified package
      // must not run. The Worker still loads it by URL, so its relative
      // import of this loader keeps resolving.
      await verifiedAsset(fetchAsset, base, manifest.workers.lane, "workers.lane");
      pool = createWorkerPool({
        laneUrl: new URL(relativeAsset(manifest.workers.lane.file, "workers.lane"), base).href,
        manifestUrl: manifestAddress.href,
        maxLanes: manifest.workers.maxLanes,
        limits: options.limits || manifest.limits,
      });
    }
    return await runNuppWasmApp({
      createHost,
      locateFile: (name) => /^[a-z][a-z0-9+.-]*:/i.test(name) ? name : new URL(name, base).href,
      app,
      sideModules,
      wasmBinary,
      effects: options.effects,
      effectHandlers: pool
        ? {...options.effectHandlers, workers: (effect) => pool.perform(effect)}
        : options.effectHandlers,
      resetLimits: options.resetLimits,
      initialize: options.initialize,
      fetch: fetchAsset,
      signal: options.signal,
      limits: options.limits || manifest.limits,
      storage: options.storage,
      storageName: options.storageName || `nupp-${manifest.app.sha256.slice(0, 24)}`,
    });
  } finally {
    pool?.close();
    for (const url of objectUrls) URL.revokeObjectURL(url);
  }
}
