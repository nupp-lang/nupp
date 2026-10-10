import {
  beginHostFrame, finishHostFrame, hostEffectBoundToFrame, hostFrameReady, hostFrameWaitable, isHostFrame,
  onHostFrameReady, performHostEffect,
} from "./host-channel.mjs";

export {closeHostChannel, createHostChannel} from "./host-channel.mjs";

// What one answer's text may hold: the guest reads it from a one-MiB slot, and
// the bridge adds its lease descriptors beside the responses.
const RESPONSE_TEXT_BUDGET = 896 * 1024;

const DEFAULT_LIMITS = Object.freeze({
  maxEffects: 256,
  maxEffectBytes: 4 * 1024 * 1024,
  maxResponseBytes: 8 * 1024 * 1024,
});

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
  if (effect.operation === "until" && typeof effect.deadline === "number" && Number.isFinite(effect.deadline) && effect.deadline >= 0) {
    effect = {...effect, operation: "sleep", milliseconds: Math.max(0, effect.deadline - (options.performance || globalThis.performance).now())};
  }
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
      // An error no scope caught is still the program's: it is reported by the next
      // GPU operation rather than lost to the console.
      device.addEventListener?.("uncapturederror", (event) => {
        options.gpuUncaptured ||= String(event?.error?.message || event?.error || "unknown error");
      });
      device.lost?.then((info) => {
        options.gpuDevice = null;
        options.gpuFailure = `WebGPU device was lost: ${info?.message || info?.reason || "unknown reason"}`;
      });
      return device;
    })();
  }
  return options.gpuDevice;
}

// WebGPU reports validation and allocation failures asynchronously, so a call that
// returned has not succeeded. Each synchronous run of device calls sits inside its
// own scopes, pushed and popped with no await between them so concurrent operations
// cannot pop each other's, and a failure it caught becomes the operation's error.
async function gpuChecked(device, work) {
  if (typeof device.pushErrorScope !== "function") return work();
  device.pushErrorScope("validation");
  device.pushErrorScope("out-of-memory");
  let value, failure, failed = false;
  try {
    value = work();
  } catch (error) {
    failure = error;
    failed = true;
  }
  const memory = device.popErrorScope();
  const validation = device.popErrorScope();
  const [outOfMemory, invalid] = await Promise.all([memory, validation]);
  if (failed) throw failure;
  if (invalid) throw new Error(`WebGPU validation failed: ${invalid.message}`);
  if (outOfMemory) throw new Error(`WebGPU is out of memory: ${outOfMemory.message}`);
  return value;
}

function gpuRuntime(options) {
  return options.gpuRuntime ||= {buffers: new Map(), kernels: new Map(), nextBuffer: 1, nextKernel: 1};
}

function memoryLease(effect, options, expectedBytes, writable = false) {
  if (!options.transfers) throw new Error("browser operation has no transfer lease table");
  return options.transfers.lease(effect.lease, expectedBytes, writable);
}

// Releases the lease an effect names, whether or not memoryLease returned it:
// the Lua side only releases after a successful answer, so every failed
// operation would otherwise strand one of the frame's leases.
function releaseEffectLease(effect, options) {
  if (options.transfers) options.transfers.release(effect.lease);
}

function gpuBuffer(runtime, id) {
  const resource = runtime.buffers.get(id);
  if (!resource) throw new Error("browser GPU buffer handle is unknown");
  return resource;
}

function gpuBufferRange(effect, resource) {
  const offset = effect.offset === undefined ? 0 : uint32(effect.offset, "buffer byte offset");
  const bytes = effect.bytes === undefined ? resource.bytes : uint32(effect.bytes, "buffer byte length");
  if (offset % 4 !== 0 || bytes === 0 || bytes % 4 !== 0 ||
      offset > resource.bytes || bytes > resource.bytes - offset) {
    throw new Error("browser GPU transfer range is invalid");
  }
  return {offset, bytes};
}

function destroyGpuDownload(resource) {
  const download = resource.download;
  resource.download = null;
  if (!download) return;
  try { download.buffer.unmap(); } catch {}
  download.buffer.destroy();
}

async function performGpuRuntimeEffect(effect, options) {
  try {
    return await performGpuOperation(effect, options);
  } finally {
    if (GPU_LEASE_OPERATIONS.has(effect.operation)) releaseEffectLease(effect, options);
  }
}

const GPU_LEASE_OPERATIONS = new Set([
  "runtime-upload", "runtime-dispatch", "runtime-download", "runtime-read-download",
]);

async function performGpuOperation(effect, options) {
  const usage = webGpuUsage(options);
  const device = await gpuDevice(options);
  if (options.gpuFailure) throw new Error(options.gpuFailure);
  if (options.gpuUncaptured) {
    const message = options.gpuUncaptured;
    options.gpuUncaptured = null;
    throw new Error(`WebGPU device error: ${message}`);
  }
  const runtime = gpuRuntime(options);
  if (effect.operation === "runtime-open") return {driver: "webgpu"};
  if (effect.operation === "runtime-close") {
    if (!Array.isArray(effect.buffers) || !Array.isArray(effect.kernels)) {
      throw new Error("browser GPU context resource lists are invalid");
    }
    const buffers = effect.buffers.map(value => uint32(value, "buffer handle"));
    const kernels = effect.kernels.map(value => uint32(value, "kernel handle"));
    for (const id of buffers) {
      const resource = runtime.buffers.get(id);
      if (!resource) continue;
      destroyGpuDownload(resource);
      resource.buffer.destroy();
      runtime.buffers.delete(id);
    }
    for (const id of kernels) runtime.kernels.delete(id);
    return null;
  }
  if (effect.operation === "runtime-create-buffer") {
    const bytes = uint32(effect.bytes, "buffer byte length");
    if (bytes === 0 || bytes % 4 !== 0) throw new Error("browser GPU buffers need a positive four-byte size");
    const buffer = await gpuChecked(device, () =>
      device.createBuffer({size: bytes, usage: usage.STORAGE | usage.COPY_DST | usage.COPY_SRC}));
    const id = runtime.nextBuffer++;
    runtime.buffers.set(id, {bytes, buffer, download: null});
    return {buffer: id};
  }
  if (effect.operation === "runtime-destroy-buffer") {
    const resource = gpuBuffer(runtime, uint32(effect.buffer, "buffer handle"));
    destroyGpuDownload(resource);
    resource.buffer.destroy();
    runtime.buffers.delete(effect.buffer);
    return null;
  }
  if (effect.operation === "runtime-compile") {
    if (typeof effect.wgsl !== "string" || effect.wgsl.length === 0 ||
        typeof effect.entrypoint !== "string" || effect.entrypoint.length === 0 ||
        !Number.isInteger(effect.readonly) || effect.readonly < 0 ||
        !Number.isInteger(effect.writable) || effect.writable < 1 ||
        effect.readonly + effect.writable > 8 ||
        !Number.isInteger(effect.uniformBytes) ||
        effect.uniformBytes < 4 * (1 + 2 * (effect.readonly + effect.writable)) ||
        effect.uniformBytes > 128 ||
        effect.uniformBytes % 4 !== 0 || !Number.isInteger(effect.threads) || effect.threads < 1 || effect.threads > 256) {
      throw new Error("browser GPU kernel descriptor is invalid");
    }
    const module = await gpuChecked(device, () => device.createShaderModule({code: effect.wgsl}));
    const descriptor = {layout: "auto", compute: {module, entryPoint: effect.entrypoint}};
    const pipeline = device.createComputePipelineAsync
      ? await device.createComputePipelineAsync(descriptor)
      : await gpuChecked(device, () => device.createComputePipeline(descriptor));
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
    const range = gpuBufferRange(effect, resource);
    const lease = memoryLease(effect, options, range.bytes);
    await gpuChecked(device, () => device.queue.writeBuffer(resource.buffer, range.offset, lease.view));
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
    // One dimension holds at most the device's per-dimension workgroup count, so
    // a longer dispatch folds into rows of that many, as the native provider
    // does; the generated shader rebuilds the linear index from the row and
    // retires the tail of the last one. Past as many rows WebGPU would drop the
    // dispatch and report nothing to the caller, so refuse it here, in the
    // native provider's words.
    const groups = Math.ceil(count / kernel.threads);
    const limit = device.limits?.maxComputeWorkgroupsPerDimension ?? 65535;
    const columns = Math.min(groups, limit);
    const rows = groups > limit ? Math.ceil(groups / limit) : 1;
    if (rows > limit) {
      throw new Error(`GPU dispatch workgroup count [${columns}, ${rows}, 1] exceeds the per-dimension limit ${limit}`);
    }
    const lease = memoryLease(effect, options, kernel.uniformBytes);
    const entries = [];
    let binding = 0;
    for (const id of effect.read) entries.push({binding: binding++, resource: {buffer: gpuBuffer(runtime, uint32(id, "read buffer")).buffer}});
    for (const id of effect.write) entries.push({binding: binding++, resource: {buffer: gpuBuffer(runtime, uint32(id, "write buffer")).buffer}});
    let uniform;
    try {
      await gpuChecked(device, () => {
        uniform = device.createBuffer({size: kernel.uniformBytes, usage: usage.UNIFORM | usage.COPY_DST});
        device.queue.writeBuffer(uniform, 0, lease.view);
        entries.push({binding, resource: {buffer: uniform}});
        const bindGroup = device.createBindGroup({layout: kernel.pipeline.getBindGroupLayout(0), entries});
        const encoder = device.createCommandEncoder();
        const pass = encoder.beginComputePass();
        pass.setPipeline(kernel.pipeline);
        pass.setBindGroup(0, bindGroup);
        pass.dispatchWorkgroups(columns, rows);
        pass.end();
        device.queue.submit([encoder.finish()]);
      });
    } finally {
      uniform?.destroy();
    }
    return null;
  }
  if (effect.operation === "runtime-enqueue-download") {
    const resource = gpuBuffer(runtime, uint32(effect.buffer, "buffer handle"));
    const range = gpuBufferRange(effect, resource);
    if (resource.download) throw new Error("browser GPU buffer already has a queued download");
    let readback;
    try {
      await gpuChecked(device, () => {
        readback = device.createBuffer({size: range.bytes, usage: usage.MAP_READ | usage.COPY_DST});
        const encoder = device.createCommandEncoder();
        encoder.copyBufferToBuffer(resource.buffer, range.offset, readback, 0, range.bytes);
        device.queue.submit([encoder.finish()]);
      });
    } catch (error) {
      readback?.destroy();
      throw error;
    }
    if (resource.download) {
      readback.destroy();
      throw new Error("browser GPU buffer already has a queued download");
    }
    const download = {buffer: readback, bytes: range.bytes, ready: false, synchronized: false, error: null};
    resource.download = download;
    download.promise = Promise.resolve(readback.mapAsync(webGpuMapMode(options).READ)).then(
      () => { download.ready = true; },
      (error) => { download.error = error; },
    );
    return null;
  }
  if (effect.operation === "runtime-read-download") {
    const resource = gpuBuffer(runtime, uint32(effect.buffer, "buffer handle"));
    const download = resource.download;
    if (!download || !download.synchronized || !download.ready || download.error) {
      throw new Error("browser GPU download is not synchronized");
    }
    try {
      memoryLease(effect, options, download.bytes, true).view
        .set(new Uint8Array(download.buffer.getMappedRange()));
      return null;
    } finally {
      destroyGpuDownload(resource);
    }
  }
  if (effect.operation === "runtime-download") {
    let readback;
    try {
      const resource = gpuBuffer(runtime, uint32(effect.buffer, "buffer handle"));
      const range = gpuBufferRange(effect, resource);
      memoryLease(effect, options, range.bytes, true);
      await gpuChecked(device, () => {
        readback = device.createBuffer({size: range.bytes, usage: usage.MAP_READ | usage.COPY_DST});
        const encoder = device.createCommandEncoder();
        encoder.copyBufferToBuffer(resource.buffer, range.offset, readback, 0, range.bytes);
        device.queue.submit([encoder.finish()]);
      });
      await readback.mapAsync(webGpuMapMode(options).READ);
      // Mapping yields to the host. Memory may grow or the lease may be revoked
      // before it completes, so project a fresh checked view at the actual write.
      memoryLease(effect, options, range.bytes, true).view.set(new Uint8Array(readback.getMappedRange()));
      readback.unmap();
      return null;
    } finally {
      if (readback) readback.destroy();
    }
  }
  if (effect.operation === "runtime-synchronize") {
    if (device.queue.onSubmittedWorkDone) await device.queue.onSubmittedWorkDone();
    for (const resource of runtime.buffers.values()) {
      const download = resource.download;
      if (!download) continue;
      await download.promise;
      if (download.error) {
        destroyGpuDownload(resource);
        throw download.error;
      }
      download.synchronized = true;
    }
    return null;
  }
  throw new Error("unsupported browser GPU runtime operation");
}

async function performGpuEffect(effect, options) {
  if (typeof effect.operation === "string" && effect.operation.startsWith("runtime-")) {
    return performGpuRuntimeEffect(effect, options);
  }
  throw new Error("unsupported browser GPU operation");
}

async function performHttpEffect(effect, options) {
  if (effect.operation === "release-body") {
    return {released: options.httpBodies?.delete(effect.body) === true};
  }
  if (effect.operation === "read-body") {
    const saved = options.httpBodies?.get(effect.body);
    if (!saved) throw new Error("browser HTTP body was released");
    try {
      if (options.signal?.aborted) throw abortError(options.signal);
      const destination = memoryLease(effect, options, saved.length, true);
      if (destination.bytes !== saved.length) throw new Error("browser HTTP body lease has the wrong length");
      let at = 0;
      for (const chunk of saved.chunks) { destination.view.set(chunk, at); at += chunk.length; }
      return {bytes: at};
    } finally {
      options.httpBodies.delete(effect.body);
      releaseEffectLease(effect, options);
    }
  }
  if (typeof effect.url !== "string" || !/^https?:\/\//i.test(effect.url)) {
    throw new Error("browser HTTP effects require an absolute http or https URL");
  }
  if (options.signal?.aborted) throw abortError(options.signal);
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
    // Fetch owns its request bytes independently of Wasm memory growth.
    const input = effect.bodyLease === undefined ? undefined : memoryLease({lease: effect.bodyLease}, options);
    if (input && input.bytes > options.limits.maxEffectBytes) throw new Error("browser HTTP request body exceeded the effect byte limit");
    const body = input ? new Uint8Array(input.view)
      : effect.bodyBase64 === undefined ? undefined : base64ToBytes(effect.bodyBase64, "HTTP request body");
    const response = await (options.fetch || globalThis.fetch)(effect.url, {
      method: effect.method || "GET",
      headers,
      body,
      redirect: "follow",
      signal: controller.signal,
    });
    const protocolLimit = effect.memoryResponse ? options.limits.maxResponseBytes : Math.floor(options.limits.maxResponseBytes * 3 / 4);
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
    if (options.signal?.aborted) throw abortError(options.signal);
    if (effect.memoryResponse) {
      options.httpBodies ||= new Map();
      const retained = Array.from(options.httpBodies.values()).reduce((total, entry) => total + entry.length, 0);
      if (retained + length > options.limits.maxResponseBytes) throw new Error("browser HTTP retained bodies exceeded the byte limit");
      const body = options.nextHttpBody = (options.nextHttpBody || 0) + 1;
      options.httpBodies.set(body, {chunks, length});
      return {status: response.status, url: response.url || effect.url, headers: Array.from(response.headers.entries()), body, bodyBytes: length};
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
    if (effect.bodyLease !== undefined) releaseEffectLease({lease: effect.bodyLease}, options);
    if (timeout !== undefined) clearTimeout(timeout);
    options.signal?.removeEventListener("abort", abort);
  }
}

function filesState(options, requireAvailable = true) {
  if (!options.files) {
    const storage = options.storage || globalThis.navigator?.storage;
    options.files = {
      storage,
      available: typeof storage?.getDirectory === "function",
      persistentAvailable: typeof options.requestPersistentStorage === "function" ||
        typeof storage?.persist === "function",
      requestPersistentStorage: options.requestPersistentStorage ||
        (typeof storage?.persist === "function" ? () => storage.persist() : undefined),
      handles: new Map(),
      nextHandle: 1,
    };
  }
  const state = options.files;
  state.handles ||= new Map();
  state.nextHandle ||= 1;
  if (requireAvailable && !state.available) throw new Error("Origin Private File System is unavailable");
  return state;
}

function fileParts(effect) {
  if (!Array.isArray(effect.parts) || effect.parts.length < 3 ||
      effect.parts.some((part) => typeof part !== "string" || part.length === 0 ||
        part === "." || part === ".." || part.includes("/") || part.includes("\\"))) {
    throw new Error("browser file path is invalid");
  }
  if (effect.parts[0] !== effect.root || !["configuration", "data", "cache"].includes(effect.root)) {
    throw new Error("browser file root is invalid");
  }
  return effect.parts;
}

async function filesRoot(state) {
  // Memoize the directory, not a failure to reach it: caching a rejection would
  // replay one transient refusal for every later file effect in the run.
  state.rootPromise ||= Promise.resolve(state.storage.getDirectory()).catch((error) => {
    state.rootPromise = undefined;
    throw error;
  });
  return state.rootPromise;
}

async function directoryAt(state, parts, create, through = parts.length) {
  let directory = await filesRoot(state);
  for (let index = 0; index < through; index++) {
    directory = await directory.getDirectoryHandle(parts[index], {create});
  }
  return directory;
}

function openFile(state, value) {
  if (!Number.isSafeInteger(value) || value < 1) throw new Error("browser file handle is invalid");
  const file = state.handles.get(value);
  if (!file) throw new Error("browser file handle is closed or unknown");
  return file;
}

async function performFilesEffectNow(effect, options) {
  const state = filesState(options, effect.operation !== "capabilities");
  if (effect.operation === "capabilities") {
    return {available: state.available === true, persistentAvailable: state.persistentAvailable === true};
  }
  if (effect.operation === "persist") {
    if (!state.requestPersistentStorage) throw new Error("the browser host has no main-thread persistence relay");
    return {granted: await state.requestPersistentStorage() === true};
  }
  if (effect.operation === "file-close") {
    const file = openFile(state, effect.handle);
    state.handles.delete(effect.handle);
    file.access.close();
    return {closed: true};
  }
  if (effect.operation === "file-size") {
    const size = openFile(state, effect.handle).access.getSize();
    if (!Number.isSafeInteger(size) || size < 0) throw new Error("browser file size is invalid");
    return {size};
  }
  if (effect.operation === "file-seek") {
    const file = openFile(state, effect.handle);
    if (!Number.isSafeInteger(effect.offset) || ![0, 1, 2].includes(effect.origin)) {
      throw new Error("browser file seek is invalid");
    }
    const base = effect.origin === 0 ? 0 : effect.origin === 1 ? file.cursor : file.access.getSize();
    const position = Math.max(0, base + effect.offset);
    if (!Number.isSafeInteger(position)) throw new Error("browser file position exceeds the exact integer range");
    file.cursor = position;
    return {position};
  }
  if (effect.operation === "file-read") {
    const file = openFile(state, effect.handle);
    if (!file.readable) throw new Error("file is not open for reading");
    if (!Number.isSafeInteger(effect.count) || effect.count < 1) throw new Error("browser file read count is invalid");
    const lease = memoryLease(effect, options, effect.count, true);
    try {
      const bytes = file.access.read(lease.view, {at: file.cursor});
      if (!Number.isSafeInteger(bytes) || bytes < 0 || bytes > effect.count) {
        throw new Error("browser file read returned an invalid byte count");
      }
      file.cursor += bytes;
      return {bytes};
    } finally {
      releaseEffectLease(effect, options);
    }
  }
  if (effect.operation === "file-write") {
    const file = openFile(state, effect.handle);
    if (!file.writable) throw new Error("file is not open for writing");
    if (!Number.isSafeInteger(effect.count) || effect.count < 0) throw new Error("browser file write count is invalid");
    const lease = memoryLease(effect, options, effect.count);
    try {
      if (file.appending) file.cursor = file.access.getSize();
      let bytes = 0;
      while (bytes < effect.count) {
        const wrote = file.access.write(lease.view.subarray(bytes), {at: file.cursor});
        if (!Number.isSafeInteger(wrote) || wrote < 1 || wrote > effect.count - bytes) {
          throw new Error("browser file write returned an invalid byte count");
        }
        bytes += wrote;
        file.cursor += wrote;
      }
      return {bytes};
    } finally {
      releaseEffectLease(effect, options);
    }
  }
  if (effect.operation === "file-flush") {
    openFile(state, effect.handle).access.flush();
    return {flushed: true};
  }
  const parts = fileParts(effect);
  if (effect.operation === "create-directory") {
    await directoryAt(state, parts, true);
    return {created: true};
  }
  const parent = await directoryAt(state, parts, false, parts.length - 1);
  const name = parts[parts.length - 1];
  if (effect.operation === "open") {
    const modes = {
      r: {mustExist: true, readable: true, writable: false},
      w: {mustExist: false, readable: false, writable: true, truncate: true},
      a: {mustExist: false, readable: false, writable: true, appending: true},
      "r+": {mustExist: true, readable: true, writable: true},
      "w+": {mustExist: false, readable: true, writable: true, truncate: true},
      "a+": {mustExist: false, readable: true, writable: true, appending: true},
    };
    const mode = modes[effect.mode];
    if (!mode) throw new Error("unknown browser file mode");
    const file = await parent.getFileHandle(name, {create: !mode.mustExist});
    if (typeof file.createSyncAccessHandle !== "function") {
      throw new Error("synchronous OPFS file handles are unavailable");
    }
    const access = await file.createSyncAccessHandle();
    try {
      if (mode.truncate) access.truncate(0);
      let handle = state.nextHandle++;
      while (handle === 0 || state.handles.has(handle)) handle = state.nextHandle++;
      state.handles.set(handle, {access, cursor: 0, ...mode});
      return {handle};
    } catch (error) {
      access.close();
      throw error;
    }
  }
  if (effect.operation === "info") {
    try {
      const handle = await parent.getFileHandle(name);
      const file = await handle.getFile();
      return {kind: "file", size: file.size, modified: file.lastModified / 1000};
    } catch (fileError) {
      try {
        await parent.getDirectoryHandle(name);
        return {kind: "directory", size: 0, modified: 0};
      } catch {
        throw fileError;
      }
    }
  }
  if (effect.operation === "remove") {
    await parent.removeEntry(name, {recursive: effect.recursive === true});
    return {removed: true};
  }
  if (effect.operation === "list") {
    const directory = await parent.getDirectoryHandle(name);
    const entries = [];
    for await (const [entryName, handle] of directory.entries()) {
      entries.push({name: entryName, kind: handle.kind === "directory" ? "directory" : "file"});
    }
    return entries;
  }
  throw new Error(`unsupported browser file operation ${effect.operation}`);
}

async function performFilesEffect(effect, options) {
  // File cleanup is queued from a non-suspending ownership terminal. Preserve
  // request order so a close and a later open in one effect batch cannot race.
  const state = filesState(options, false);
  const previous = state.operations || Promise.resolve();
  const current = previous.catch(() => {}).then(() => performFilesEffectNow(effect, options));
  state.operations = current;
  return current;
}

async function performEffect(effect, options) {
  if (!Number.isInteger(effect?.id) || effect.id < 1) {
    return {id: effect?.id, ok: false, error: "browser effect id is invalid"};
  }
  try {
    let value;
    const supplied = options.effectHandlers?.[effect.kind];
    if (supplied) value = await supplied(effect, options);
    else if (effect.kind === "http") value = await performHttpEffect(effect, options);
    else if (effect.kind === "files") value = await performFilesEffect(effect, options);
    else if (effect.kind === "time") value = await performTimeEffect(effect, options);
    else if (effect.kind === "random") value = await performRandomEffect(effect, options);
    else if (effect.kind === "system") {
      const count = globalThis.navigator?.hardwareConcurrency;
      value = {availableParallelism: Number.isInteger(count) && count > 0 ? count : 1};
    }
    else if (effect.kind === "sha256") value = await performSha256Effect(effect, options);
    else if (effect.kind === "hmac-sha256") value = await performHmacEffect(effect, options);
    else if (effect.kind === "gpu") value = await performGpuEffect(effect, options);
    else if (effect.kind === "host") value = await performHostEffect(effect, options);
    else throw new Error(`unsupported browser effect ${effect.kind}`);
    return {id: effect.id, ok: true, value};
  } catch (error) {
    return {id: effect.id, ok: false, error: String(error?.message || error)};
  }
}

// A transfer lease belongs to the frame that carried it: the guest takes its bytes
// back when the frame is answered, so a request naming one settles inside it.
function boundToFrame(effect) {
  if (effect?.kind === "host") return hostEffectBoundToFrame(effect);
  return effect?.lease !== undefined || effect?.bodyLease !== undefined ||
    effect?.resultLease !== undefined || effect?.spans !== undefined;
}

// Answers what fits the guest's text slot. Responses held to this frame always
// go, since their leases return with it; settled detached ones fill the rest in
// the order they settled, and what is left waits for the next frame.
function packedResponses(held, detached) {
  const responses = [...held];
  let used = held.reduce((total, response) => total + JSON.stringify(response).length + 1, 64);
  let taken = 0;
  while (taken < detached.settled.length) {
    const size = JSON.stringify(detached.settled[taken]).length + 1;
    if (used + size > RESPONSE_TEXT_BUDGET && responses.length > 0) break;
    used += size;
    taken++;
  }
  responses.push(...detached.settled.splice(0, taken));
  return responses;
}

function detachedEffects(options) {
  return options.detachedEffects ||= {pending: 0, settled: [], wake: null};
}

function nextHostTurn() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

// A frame says how long it may be held. `any`: the application has nothing else to
// do, so answer once something settles. `turn`: it owes the event loop a turn and
// has work of its own, so answer after one with whatever has settled. Either way a
// request without a lease is not held for its batch: a short sleep shipped beside a
// scope's deadline timer is answered when it ends, and the timer in a later frame.
// A frame naming neither is answered once every request it carries has settled.
export async function handleBrowserEffects(message, options = {}) {
  const wake = message?.wake;
  if (wake !== undefined && wake !== "any" && wake !== "turn") {
    throw new Error("the Nupp app yielded an unknown browser effect wake mode");
  }
  if (message?.kind !== "poll" && (message?.kind !== "effects" || !Array.isArray(message.requests))) {
    throw new Error("the Nupp app yielded an unknown browser effect message");
  }
  const detached = detachedEffects(options);
  const held = [];
  // A `nupp.host` frame is read after everything else the frame carries, so an
  // upload it names has arrived, and answered last, with whatever its inbox can
  // take once the frame has waited.
  const hostFrames = [];
  if (message.kind === "effects") {
    options.limits ||= checkedLimits(options.limitOverrides);
    if (message.requests.length > options.limits.maxEffects) {
      throw new Error(`browser application yielded more than ${options.limits.maxEffects} effects`);
    }
    for (const effect of message.requests) {
      if (isHostFrame(effect)) {
        hostFrames.push(effect);
        continue;
      }
      const settling = performEffect(effect, options);
      if (wake === undefined || boundToFrame(effect)) {
        held.push(settling);
        continue;
      }
      detached.pending += 1;
      settling.then((response) => {
        detached.pending -= 1;
        detached.settled.push(response);
        const notify = detached.wake;
        detached.wake = null;
        notify?.();
      });
    }
  }
  for (const effect of hostFrames) beginHostFrame(effect, options);
  const responses = await Promise.all(held);
  if (wake === "any") {
    const hostReady = hostFrames.length > 0 && hostFrameReady(options);
    if (responses.length === 0 && detached.settled.length === 0 && !hostReady) {
      const hostWaits = hostFrames.length > 0 && hostFrameWaitable(options);
      if (detached.pending > 0 || hostWaits) {
        await new Promise((resolve) => {
          detached.wake = resolve;
          if (hostWaits) onHostFrameReady(options, resolve);
        });
        detached.wake = null;
        onHostFrameReady(options, null);
      } else {
        await nextHostTurn();
      }
    }
  } else if (message.kind === "poll" || wake === "turn") {
    await nextHostTurn();
  }
  const answered = packedResponses(responses, detached);
  for (const effect of hostFrames) {
    try {
      answered.push({id: effect.id, ok: true, value: finishHostFrame(effect, options)});
    } catch (error) {
      answered.push({id: effect.id, ok: false, error: String(error?.message || error)});
    }
  }
  return {responses: answered};
}
