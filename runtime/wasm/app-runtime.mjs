const DEFAULT_LIMITS = Object.freeze({
  maxEffects: 256,
  maxEffectBytes: 4 * 1024 * 1024,
  maxResponseBytes: 8 * 1024 * 1024,
  deadlineMs: 30_000,
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

function memoryLease(effect, options, expectedBytes, writable = false) {
  if (options.transfers) return options.transfers.lease(effect.lease, expectedBytes, writable);
  const module = options.wasmModule;
  const id = effect.lease;
  if (!module || !Number.isInteger(id) || id < 1 || !module._nupp_wasm_lease_address ||
      !module._nupp_wasm_lease_size || !module._nupp_wasm_release_lease) {
    throw new Error("browser operation has no valid Wasm transfer lease");
  }
  const pointer = module._nupp_wasm_lease_address(id);
  const bytes = module._nupp_wasm_lease_size(id);
  if (!pointer || (expectedBytes !== undefined && bytes !== expectedBytes)) {
    throw new Error("browser transfer lease is stale or has the wrong size");
  }
  if (!Number.isInteger(pointer) || pointer < 0 || !Number.isInteger(bytes) || bytes < 0 ||
      !module.HEAPU8 || pointer > module.HEAPU8.byteLength || bytes > module.HEAPU8.byteLength - pointer) {
    throw new Error("browser transfer lease is outside Wasm memory");
  }
  if (writable && (!module._nupp_wasm_lease_writable || module._nupp_wasm_lease_writable(id) !== 1)) {
    throw new Error("browser destination requires a writable transfer lease");
  }
  return {id, bytes, view: module.HEAPU8.subarray(pointer, pointer + bytes), module};
}

// Releases the lease an effect names, whether or not memoryLease returned it:
// the Lua side only releases after a successful answer, so every failed
// operation would otherwise strand one of the fixed lease slots.
function releaseEffectLease(effect, options) {
  if (options.transfers) { options.transfers.release(effect.lease); return; }
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
    const lease = memoryLease(effect, options, resource.bytes);
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
    const lease = memoryLease(effect, options, kernel.uniformBytes);
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
      memoryLease(effect, options, resource.bytes, true);
      readback = device.createBuffer({size: resource.bytes, usage: usage.MAP_READ | usage.COPY_DST});
      const encoder = device.createCommandEncoder();
      encoder.copyBufferToBuffer(resource.buffer, 0, readback, 0, resource.bytes);
      device.queue.submit([encoder.finish()]);
      await readback.mapAsync(webGpuMapMode(options).READ);
      // Mapping yields to the host. Memory may grow or the lease may be revoked
      // before it completes, so project a fresh checked view at the actual write.
      memoryLease(effect, options, resource.bytes, true).view.set(new Uint8Array(readback.getMappedRange()));
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

async function performHttpEffect(effect, options) {
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

function filesState(options) {
  const state = options.files;
  if (!state?.available) throw new Error("Origin Private File System is unavailable");
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

async function performFilesEffect(effect, options) {
  const state = filesState(options);
  if (effect.operation === "persist") {
    if (!state.requestPersistentStorage) throw new Error("the browser host has no main-thread persistence relay");
    return {granted: await state.requestPersistentStorage() === true};
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
      else throw new Error(`unsupported browser effect ${effect.kind}`);
      return {id: effect.id, ok: true, value};
    } catch (error) {
      return {id: effect.id, ok: false, error: String(error?.message || error)};
    }
  }));
  return {responses};
}
