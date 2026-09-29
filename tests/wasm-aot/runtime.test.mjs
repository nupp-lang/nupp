import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import test from "node:test";

import { handleBrowserEffects } from "../../runtime/wasm/app-runtime.mjs";
import { runNuppLuaJITApp, runPackagedNuppLuaJITApp } from "../../runtime/luajit/app-runtime.mjs";
import { createWorkerPool } from "../../runtime/wasm/worker-pool.mjs";

globalThis.crypto ||= webcrypto;

// A guest transfer table over one heap: each lease is a window into it, and a
// release records the lease and retires it.
function heapTransfers(heap, leases, released = [], writable = () => true) {
  return {
    lease(id, expectedBytes, wantsWritable) {
      const entry = leases.get(id);
      if (!entry || (expectedBytes !== undefined && entry.bytes !== expectedBytes)) {
        throw new Error("browser transfer lease is stale or has the wrong size");
      }
      if (wantsWritable && !writable(id)) throw new Error("browser destination requires a writable transfer lease");
      return {id, bytes: entry.bytes, view: heap.subarray(entry.pointer, entry.pointer + entry.bytes)};
    },
    release(id) {
      released.push(id);
      leases.delete(id);
    },
  };
}

test("browser system effects report usable parallelism", async () => {
  const result = await handleBrowserEffects({
    kind: "effects", requests: [{id: 1, kind: "system"}],
  });
  const response = result.responses[0];
  assert.equal(response.ok, true);
  assert.ok(Number.isInteger(response.value.availableParallelism));
  assert.ok(response.value.availableParallelism >= 1);
});

test("browser system effects respect host overrides", async () => {
  const result = await handleBrowserEffects({
    kind: "effects", requests: [{id: 1, kind: "system"}],
  }, {effectHandlers: {system: async () => ({availableParallelism: 3})}});
  assert.equal(result.responses[0].value.availableParallelism, 3);
});


test("browser HTTP effects preserve response bytes and metadata", async () => {
  const result = await handleBrowserEffects({
    kind: "effects",
    requests: [{id: 7, kind: "http", url: "https://example.test/data", method: "GET"}],
  }, {
    fetch: async () => new Response(Uint8Array.of(0, 1, 255), {
      status: 206,
      headers: {"content-type": "application/octet-stream"},
    }),
  });
  assert.deepEqual(result, {responses: [{
    id: 7,
    ok: true,
    value: {
      status: 206,
      url: "https://example.test/data",
      headers: [["content-type", "application/octet-stream"]],
      bodyBase64: "AAH/",
    },
  }]});
});

test("browser HTTP effect failures resume as protocol errors", async () => {
  const result = await handleBrowserEffects({
    kind: "effects",
    requests: [{id: 3, kind: "http", url: "file:///private/data"}],
  });
  assert.equal(result.responses[0].id, 3);
  assert.equal(result.responses[0].ok, false);
  assert.match(result.responses[0].error, /absolute http or https URL/);
});

test("browser HTTP effects enforce size, timeout, and cancellation limits", async () => {
  let result = await handleBrowserEffects({
    kind: "effects",
    requests: [{id: 1, kind: "http", url: "https://example.test", maxBytes: 2}],
  }, {fetch: async () => new Response("abc", {headers: {"content-length": "3"}})});
  assert.equal(result.responses[0].ok, false);
  assert.match(result.responses[0].error, /exceeded maxBytes/);

  result = await handleBrowserEffects({
    kind: "effects",
    requests: [{id: 2, kind: "http", url: "https://example.test", timeoutMs: 1}],
  }, {
    fetch: async (_url, request) => new Promise((_resolve, reject) => {
      request.signal.addEventListener("abort", () => reject(request.signal.reason), {once: true});
    }),
  });
  assert.equal(result.responses[0].ok, false);
  assert.match(result.responses[0].error, /timed out/);

  const cancelled = new AbortController();
  cancelled.abort(new Error("application cancelled"));
  let fetched = false;
  result = await handleBrowserEffects({
    kind: "effects",
    requests: [{id: 3, kind: "http", url: "https://example.test"}],
  }, {signal: cancelled.signal, fetch: async () => { fetched = true; return new Response(""); }});
  assert.equal(result.responses[0].ok, false);
  assert.match(result.responses[0].error, /application cancelled/);
  assert.equal(fetched, false);
});

function fakeOpfs() {
  class FileHandle {
    constructor(name) {
      this.kind = "file";
      this.name = name;
      this.bytes = new Uint8Array();
      this.locked = false;
    }
    async getFile() { return {size: this.bytes.length, lastModified: 1_700_000_000_000}; }
    async createSyncAccessHandle() {
      if (this.locked) throw new Error("file is already locked");
      this.locked = true;
      return {
        read: (output, {at}) => {
          const count = Math.min(output.length, Math.max(0, this.bytes.length - at));
          output.set(this.bytes.subarray(at, at + count));
          return count;
        },
        write: (input, {at}) => {
          const grown = new Uint8Array(Math.max(this.bytes.length, at + input.length));
          grown.set(this.bytes);
          grown.set(input, at);
          this.bytes = grown;
          return input.length;
        },
        getSize: () => this.bytes.length,
        truncate: (size) => { this.bytes = this.bytes.slice(0, size); },
        flush() {},
        close: () => { this.locked = false; },
      };
    }
  }
  class DirectoryHandle {
    constructor(name = "") { this.kind = "directory"; this.name = name; this.children = new Map(); }
    async getDirectoryHandle(name, {create = false} = {}) {
      let child = this.children.get(name);
      if (!child && create) { child = new DirectoryHandle(name); this.children.set(name, child); }
      if (!child || child.kind !== "directory") throw new Error("directory does not exist");
      return child;
    }
    async getFileHandle(name, {create = false} = {}) {
      let child = this.children.get(name);
      if (!child && create) { child = new FileHandle(name); this.children.set(name, child); }
      if (!child || child.kind !== "file") throw new Error("file does not exist");
      return child;
    }
    async removeEntry(name, {recursive = false} = {}) {
      const child = this.children.get(name);
      if (!child) throw new Error("entry does not exist");
      if (child.kind === "directory" && child.children.size && !recursive) throw new Error("directory is not empty");
      this.children.delete(name);
    }
    async *entries() { yield* this.children.entries(); }
  }
  const root = new DirectoryHandle();
  return {root, storage: {getDirectory: async () => root}};
}

test("browser file effects acquire OPFS paths and retain synchronous handles", async () => {
  const {storage} = fakeOpfs();
  const files = {
    storage, available: true, persistentAvailable: true,
    requestPersistentStorage: async () => true,
    handles: new Map(), nextHandle: 1, lastError: "",
  };
  const request = async (id, operation, parts = ["data", "nupp", "example"], extra = {}) => {
    const result = await handleBrowserEffects({kind: "effects", requests: [{
      id, kind: "files", operation, root: "data", parts, ...extra,
    }]}, {files});
    return result.responses[0];
  };
  assert.equal((await request(1, "create-directory")).ok, true);
  const opened = await request(2, "open", ["data", "nupp", "example", "save.bin"], {mode: "w+"});
  assert.equal(opened.ok, true);
  assert.equal(files.handles.get(opened.value.handle).writable, true);
  const locked = await request(3, "open", ["data", "nupp", "example", "save.bin"], {mode: "r"});
  assert.equal(locked.ok, false);
  assert.match(locked.error, /locked/);
  const transferred = (bytes, writable) => {
    const lease = {view: bytes, bytes: bytes.length, released: false};
    return {
      lease(_id, expected, needsWrite) {
        assert.equal(expected, bytes.length);
        assert.equal(needsWrite === true, writable);
        return lease;
      },
      release() { lease.released = true; },
      get released() { return lease.released; },
    };
  };
  let transfers = transferred(Uint8Array.of(1, 2, 3, 4), false);
  let result = await handleBrowserEffects({kind: "effects", requests: [{
    id: 4, kind: "files", operation: "file-write", handle: opened.value.handle, lease: 1, count: 4,
  }]}, {files, transfers});
  assert.deepEqual(result.responses[0].value, {bytes: 4});
  assert.equal(transfers.released, true);
  assert.deepEqual((await request(5, "file-size", [], {handle: opened.value.handle})).value, {size: 4});
  assert.deepEqual((await request(6, "file-seek", [], {
    handle: opened.value.handle, offset: 1, origin: 0,
  })).value, {position: 1});
  const output = new Uint8Array(3);
  transfers = transferred(output, true);
  result = await handleBrowserEffects({kind: "effects", requests: [{
    id: 7, kind: "files", operation: "file-read", handle: opened.value.handle, lease: 2, count: 3,
  }]}, {files, transfers});
  assert.deepEqual(result.responses[0].value, {bytes: 3});
  assert.deepEqual([...output], [2, 3, 4]);
  assert.equal(transfers.released, true);
  assert.equal((await request(8, "file-flush", [], {handle: opened.value.handle})).ok, true);
  result = await handleBrowserEffects({kind: "effects", requests: [
    {id: 9, kind: "files", operation: "file-close", handle: opened.value.handle},
    {id: 10, kind: "files", operation: "open", root: "data",
      parts: ["data", "nupp", "example", "save.bin"], mode: "r"},
  ]}, {files});
  assert.equal(result.responses[0].ok, true);
  assert.equal(result.responses[1].ok, true, "queued cleanup precedes a later open in the same batch");
  assert.deepEqual((await request(11, "list")).value, [{name: "save.bin", kind: "file"}]);
  const persisted = await handleBrowserEffects({kind: "effects", requests: [{
    id: 12, kind: "files", operation: "persist",
  }]}, {files});
  assert.deepEqual(persisted.responses[0].value, {granted: true});
});

test("browser file effects initialize their default OPFS state", async () => {
  const {storage} = fakeOpfs();
  const options = {storage};
  const result = await handleBrowserEffects({kind: "effects", requests: [{
    id: 1, kind: "files", operation: "create-directory",
    root: "cache", parts: ["cache", "nupp", "example"],
  }]}, options);
  assert.equal(result.responses[0].ok, true);
  assert.equal(options.files.available, true);
  assert.equal(options.files.handles.size, 0);
});

test("browser file effects retry a storage root that refused once", async () => {
  const {storage} = fakeOpfs();
  let refusals = 1;
  const files = {
    storage: {
      getDirectory: async () => {
        if (refusals-- > 0) throw new Error("storage is busy");
        return storage.getDirectory();
      },
    },
    available: true, handles: new Map(), nextHandle: 1, lastError: "",
  };
  const request = async (id) => {
    const result = await handleBrowserEffects({kind: "effects", requests: [{
      id, kind: "files", operation: "create-directory", root: "data", parts: ["data", "nupp", "example"],
    }]}, {files});
    return result.responses[0];
  };
  const refused = await request(1);
  assert.equal(refused.ok, false);
  assert.match(refused.error, /storage is busy/);
  assert.equal((await request(2)).ok, true, "a refusal must not be cached for the rest of the run");
});

test("browser time effects use Worker clocks and cancellable timers", async () => {
  const clock = await handleBrowserEffects({
    kind: "effects",
    requests: [
      {id: 1, kind: "time", operation: "now"},
      {id: 2, kind: "time", operation: "wall"},
      {id: 3, kind: "time", operation: "sleep", milliseconds: 0},
    ],
  }, {
    performance: {now: () => 12.5},
    dateNow: () => 1_700_000_000_000,
  });
  assert.deepEqual(clock.responses, [
    {id: 1, ok: true, value: 12.5},
    {id: 2, ok: true, value: 1_700_000_000_000},
    {id: 3, ok: true, value: null},
  ]);
});

test("a waiting frame is answered when its first request settles, not its last", async () => {
  const options = {};
  const started = performance.now();
  const first = await handleBrowserEffects({
    kind: "effects",
    wake: "any",
    requests: [
      {id: 1, kind: "time", operation: "sleep", milliseconds: 5},
      {id: 2, kind: "time", operation: "sleep", milliseconds: 400},
    ],
  }, options);
  // A scope deadline ships beside its children's waits. Holding the frame for the
  // longer timer would answer a short sleep at the deadline.
  assert.deepEqual(first.responses, [{id: 1, ok: true, value: null}]);
  assert.ok(performance.now() - started < 300, "the short sleep waited on the long one");
  const later = await handleBrowserEffects({kind: "poll", operation: "a task", wake: "any"}, options);
  assert.deepEqual(later.responses, [{id: 2, ok: true, value: null}], "a detached request arrives in a later frame");
});

test("a turn frame returns after one host turn with whatever has settled", async () => {
  const turn = await handleBrowserEffects({
    kind: "effects",
    wake: "turn",
    requests: [
      {id: 1, kind: "time", operation: "now"},
      {id: 2, kind: "time", operation: "sleep", milliseconds: 60},
    ],
  }, {performance: {now: () => 3}});
  assert.deepEqual(turn.responses, [{id: 1, ok: true, value: 3}]);
});

test("a frame holds every request that names a transfer lease", async () => {
  let released = 0;
  const transfers = {
    lease: () => ({view: new Uint8Array(4), bytes: 4}),
    release: () => { released += 1; },
  };
  const result = await handleBrowserEffects({
    kind: "effects",
    wake: "any",
    requests: [
      {id: 1, kind: "time", operation: "sleep", milliseconds: 0},
      {id: 2, kind: "slow", lease: 9},
    ],
  }, {
    transfers,
    effectHandlers: {
      slow: async (effect, options) => {
        await new Promise((resolve) => setTimeout(resolve, 40));
        options.transfers.release(effect.lease);
        return "done";
      },
    },
  });
  // The lease belongs to this frame's transfer batch, which must be settled before
  // the frame is answered, so the request cannot be left for a later one.
  assert.deepEqual(result.responses.map((item) => item.id).sort(), [1, 2]);
  assert.equal(released, 1);
});

test("a frame without a wake mode answers every request it carries", async () => {
  const result = await handleBrowserEffects({
    kind: "effects",
    requests: [
      {id: 1, kind: "time", operation: "sleep", milliseconds: 0},
      {id: 2, kind: "time", operation: "sleep", milliseconds: 30},
    ],
  });
  assert.deepEqual(result.responses.map((item) => item.id), [1, 2]);
});

// A guest that asks for `frames` effect frames of one request each, then finishes.
function scriptedGuest(frames, request = {kind: "time", operation: "now"}) {
  return ({onProgress}) => {
    let sent = 0;
    queueMicrotask(() => onProgress({type: "ready"}));
    return {
      async receive() {
        if (sent === frames) return {type: "done", result: {ok: true, value: JSON.stringify("finished")}};
        sent += 1;
        return {type: "effect", result: {kind: "effects", wake: "any", requests: [{id: sent, ...request}]}};
      },
      respond() {},
      close() {},
    };
  };
}

test("a page application's budgets start over with every turn", async () => {
  // A frame loop: far more effects than one turn allows, one frame at a time.
  const result = await runNuppLuaJITApp({app: new Uint8Array(), createGuest: scriptedGuest(300)});
  assert.equal(result, "finished");
});

test("a page application refuses a turn that carries more than its limit", async () => {
  const guest = ({onProgress}) => {
    queueMicrotask(() => onProgress({type: "ready"}));
    return {
      async receive() {
        return {type: "effect", result: {kind: "effects", requests: [1, 2, 3].map((id) => ({id, kind: "time", operation: "now"}))}};
      },
      respond() {},
      close() {},
    };
  };
  await assert.rejects(
    runNuppLuaJITApp({app: new Uint8Array(), limits: {perTurn: {maxEffects: 2}}, createGuest: guest}),
    /exceeded limits\.perTurn\.maxEffects \(2\)/,
  );
});

test("a page application enforces the run limits it is given", async () => {
  await assert.rejects(
    runNuppLuaJITApp({app: new Uint8Array(), limits: {perRun: {maxEffects: 5}}, createGuest: scriptedGuest(10)}),
    /exceeded limits\.perRun\.maxEffects \(5\)/,
  );
  await assert.rejects(
    runNuppLuaJITApp({
      app: new Uint8Array(),
      limits: {perRun: {deadlineMs: 60}},
      createGuest: scriptedGuest(10, {kind: "time", operation: "sleep", milliseconds: 20}),
    }),
    /exceeded limits\.perRun\.deadlineMs \(60 ms\)/,
    "no frame starts the run deadline over",
  );
});

test("a page application refuses limits outside the perTurn and perRun tables", async () => {
  const run = (limits) => runNuppLuaJITApp({app: new Uint8Array(), limits, createGuest: scriptedGuest(0)});
  await assert.rejects(run({maxEffects: 10}), /Unknown application limit maxEffects/);
  await assert.rejects(run({perTurn: {deadlineMs: 10}}), /Unknown application limit perTurn\.deadlineMs/);
  await assert.rejects(run({perRun: {computeMs: 10}}), /Unknown application limit perRun\.computeMs/);
  await assert.rejects(run({perRun: {maxEffects: 0}}), /Invalid application limit perRun\.maxEffects/);
});

test("a page application with no run limit continues past thirty seconds", async (t) => {
  t.mock.timers.enable({apis: ["setTimeout"]});
  let answer;
  const running = runNuppLuaJITApp({
    app: new Uint8Array(),
    createGuest: scriptedGuest(1),
    effects: () => new Promise((resolve) => { answer = resolve; }),
  });
  while (!answer) await new Promise(setImmediate);
  t.mock.timers.tick(120_000);
  answer({kind: "responses", responses: []});
  assert.equal(await running, "finished");
});

// A module Worker standing in for the guest VM: it boots, asks for one effect, and
// then computes forever instead of yielding the next frame.
class SpinningGuestWorker {
  static opened = [];

  constructor(url) {
    this.url = url;
    this.terminated = false;
    SpinningGuestWorker.opened.push(this);
  }

  postMessage(message) {
    if (message.type !== "boot") return;
    queueMicrotask(() => {
      this.onmessage({data: {type: "ready"}});
      this.onmessage({data: {
        type: "effect", sequence: 1,
        result: {kind: "effects", requests: [{id: 1, kind: "time", operation: "now"}]},
      }});
    });
  }

  terminate() {
    this.terminated = true;
  }
}

test("a spinning guest trips the per-turn compute limit", async (t) => {
  const saved = globalThis.Worker;
  globalThis.Worker = SpinningGuestWorker;
  t.after(() => { globalThis.Worker = saved; });
  SpinningGuestWorker.opened = [];
  await assert.rejects(
    runNuppLuaJITApp({
      manifestUrl: "https://example.test/guest/guest-manifest.json",
      app: new Uint8Array(),
      limits: {perTurn: {computeMs: 40}},
    }),
    /exceeded limits\.perTurn\.computeMs \(40 ms\)/,
  );
  assert.equal(SpinningGuestWorker.opened.length, 1);
  assert.equal(SpinningGuestWorker.opened[0].terminated, true, "the spinning VM is terminated, not awaited");
});

// The page's Worker behind `nupp-browser-app.mjs`, recording what the entry module
// asks of it.
class FakePageWorker {
  static opened = [];

  constructor(url, options) {
    this.url = url;
    this.options = options;
    this.listeners = new Map();
    this.posted = [];
    this.terminated = false;
    FakePageWorker.opened.push(this);
  }

  addEventListener(name, handler) {
    this.listeners.set(name, [...(this.listeners.get(name) || []), handler]);
  }

  emit(name, event) {
    for (const handler of this.listeners.get(name) || []) handler(event);
  }

  postMessage(message) {
    this.posted.push(message);
  }

  terminate() {
    this.terminated = true;
  }
}

let entryInstances = 0;

// A fresh instance of the entry module, as a page that imports it gets.
async function importEntry(t) {
  const saved = globalThis.Worker;
  globalThis.Worker = FakePageWorker;
  t.after(() => { globalThis.Worker = saved; });
  FakePageWorker.opened = [];
  entryInstances += 1;
  return import(`../../runtime/wasm/browser-entry.mjs?instance=${entryInstances}`);
}

test("importing the entry module launches nothing until the page calls run", async (t) => {
  const entry = await importEntry(t);
  await new Promise(setImmediate);
  entry.cancel();
  assert.equal(FakePageWorker.opened.length, 0, "importing, or cancelling before run, starts no Worker");
  assert.equal(entry.ready, undefined);
  assert.equal(entry.default, undefined);
  const limits = {perRun: {deadlineMs: 60_000}};
  const running = entry.run({limits});
  assert.equal(FakePageWorker.opened.length, 1);
  const [worker] = FakePageWorker.opened;
  assert.equal(worker.options.type, "module");
  const request = worker.posted.find((message) => message.type === "run");
  assert.deepEqual(request.limits, limits, "the page's own options reach the application");
  assert.match(request.manifest, /\/nupp-browser-app\.json$/);
  await assert.rejects(entry.run(), /already started/);
  worker.emit("message", {data: {id: request.id, ok: true, result: 3}});
  assert.equal(await running, 3);
  entry.close();
  assert.equal(worker.terminated, true);
});

test("a page application runs past thirty seconds when its limits allow", async (t) => {
  t.mock.timers.enable({apis: ["setTimeout"]});
  const entry = await importEntry(t);
  const running = entry.run();
  const [worker] = FakePageWorker.opened;
  t.mock.timers.tick(120_000);
  assert.equal(worker.terminated, false, "no deadline outside limits ends the Worker");
  const request = worker.posted.find((message) => message.type === "run");
  worker.emit("message", {data: {id: request.id, ok: true, result: "finished"}});
  assert.equal(await running, "finished");
  entry.close();
});

test("browser Web Crypto effects provide random, SHA-256, and HMAC", async () => {
  const result = await handleBrowserEffects({
    kind: "effects",
    requests: [
      {id: 1, kind: "random", count: 16, wallTime: true},
      {id: 2, kind: "sha256", bytesBase64: "YWJj"},
      {id: 3, kind: "hmac-sha256", keyBase64: "a2V5", messageBase64: "YWJj"},
    ],
  }, {crypto: webcrypto, dateNow: () => 1234});
  assert.equal(Buffer.from(result.responses[0].value.bytesBase64, "base64").length, 16);
  assert.equal(result.responses[0].value.wallTimeMs, 1234);
  assert.equal(
    result.responses[1].value,
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  );
  assert.equal(
    Buffer.from(result.responses[2].value.digestBase64, "base64").toString("hex"),
    "9c196e32dc0175f86f4b1cb89289d6619de6bee699e4c378e68309ed97a1a6ab",
  );
});

test("browser WebGPU runtime moves bytes through transfer leases", async () => {
  const heap = new Uint8Array(128);
  const released = [];
  const leases = new Map([
    [1, {pointer: 8, bytes: 8}],
    [2, {pointer: 16, bytes: 8}],
    [3, {pointer: 24, bytes: 24}],
    [4, {pointer: 48, bytes: 8}],
    [5, {pointer: 56, bytes: 4}],
    [6, {pointer: 60, bytes: 4}],
    [7, {pointer: 60, bytes: 4}],
    [8, {pointer: 56, bytes: 4}],
  ]);
  new Uint32Array(heap.buffer, 8, 2).set([4, 9]);
  // count, input count, output count, input offset, output offset, scalar.
  new Uint32Array(heap.buffer, 24, 6).set([2, 2, 2, 0, 0, 7]);
  new Uint32Array(heap.buffer, 56, 1).set([23]);

  const device = {
    lost: {then() {}},
    queue: {
      writeBuffer(buffer, offset, value) {
        buffer.bytes.set(new Uint8Array(value.buffer, value.byteOffset, value.byteLength), offset);
      },
      submit([command]) {
        if (command.pass) {
          const [input, output, uniform] = command.pass.group.entries.map((entry) => entry.resource.buffer);
          const values = new Uint32Array(input.bytes.buffer, input.bytes.byteOffset, input.bytes.byteLength / 4);
          const result = new Uint32Array(output.bytes.buffer, output.bytes.byteOffset, output.bytes.byteLength / 4);
          const words = new Uint32Array(uniform.bytes.buffer, uniform.bytes.byteOffset, uniform.bytes.byteLength / 4);
          for (let index = 0; index < words[0]; index += 1) result[index] = values[index] + words[5];
        }
        if (command.copy) {
          const {source, sourceOffset, destination, destinationOffset, bytes} = command.copy;
          destination.bytes.set(source.bytes.subarray(sourceOffset, sourceOffset + bytes), destinationOffset);
        }
      },
      async onSubmittedWorkDone() {},
    },
    createShaderModule: () => ({}),
    createComputePipelineAsync: async () => ({getBindGroupLayout: () => ({})}),
    createBuffer({size}) {
      return {
        bytes: new Uint8Array(size),
        destroyed: false,
        destroy() { this.destroyed = true; },
        async mapAsync() {},
        getMappedRange() { return this.bytes.buffer; },
        unmap() {},
      };
    },
    createBindGroup: ({entries}) => ({entries}),
    createCommandEncoder() {
      const command = {
        beginComputePass() {
          command.pass = {
            setPipeline() {},
            setBindGroup(_slot, group) { command.pass.group = group; },
            dispatchWorkgroups() {},
            end() {},
          };
          return command.pass;
        },
        copyBufferToBuffer(source, sourceOffset, destination, destinationOffset, bytes) {
          command.copy = {source, sourceOffset, destination, destinationOffset, bytes};
        },
        finish: () => command,
      };
      return command;
    },
  };
  const options = {
    gpu: {requestAdapter: async () => ({requestDevice: async () => device})},
    GPUBufferUsage: {STORAGE: 1, COPY_DST: 2, COPY_SRC: 4, UNIFORM: 8, MAP_READ: 16},
    GPUMapMode: {READ: 1},
    transfers: heapTransfers(heap, leases, released),
  };
  const run = async (id, operation) => {
    const result = await handleBrowserEffects({kind: "effects", requests: [{id, kind: "gpu", ...operation}]}, options);
    assert.deepEqual(result.responses[0].ok, true, result.responses[0].error);
    return result.responses[0].value;
  };
  const fails = async (id, operation, message) => {
    const result = await handleBrowserEffects({kind: "effects", requests: [{id, kind: "gpu", ...operation}]}, options);
    assert.equal(result.responses[0].ok, false);
    assert.match(result.responses[0].error, message);
  };

  await run(1, {operation: "runtime-open"});
  const input = await run(2, {operation: "runtime-create-buffer", bytes: 8});
  const output = await run(3, {operation: "runtime-create-buffer", bytes: 8});
  const kernel = await run(4, {
    operation: "runtime-compile", wgsl: "@compute @workgroup_size(1) fn main() {}", entrypoint: "main",
    readonly: 1, writable: 1, uniformBytes: 24, threads: 1,
  });
  await fails(20, {
    operation: "runtime-compile", wgsl: "@compute @workgroup_size(1) fn main() {}", entrypoint: "main",
    readonly: 1, writable: 1, uniformBytes: 4, threads: 1,
  }, /descriptor is invalid/);
  await run(5, {operation: "runtime-upload", buffer: input.buffer, lease: 1});
  await run(6, {
    operation: "runtime-dispatch", kernel: kernel.kernel, read: [input.buffer], write: [output.buffer], count: 2, lease: 3,
  });
  await run(7, {operation: "runtime-enqueue-download", buffer: output.buffer, offset: 0, bytes: 8});
  await run(8, {operation: "runtime-synchronize"});
  await run(9, {operation: "runtime-read-download", buffer: output.buffer, lease: 2});

  assert.deepEqual(Array.from(new Uint32Array(heap.buffer, 16, 2)), [11, 16]);
  assert.deepEqual(released, [1, 3, 2]);

  const partial = await run(10, {operation: "runtime-create-buffer", bytes: 12});
  await fails(11, {operation: "runtime-upload", buffer: partial.buffer, offset: 10, bytes: 4, lease: 8}, /range is invalid/);
  await run(12, {operation: "runtime-upload", buffer: partial.buffer, offset: 4, bytes: 4, lease: 5});
  await run(13, {operation: "runtime-enqueue-download", buffer: partial.buffer, offset: 4, bytes: 4});
  await fails(14, {operation: "runtime-enqueue-download", buffer: partial.buffer, offset: 4, bytes: 4}, /already has a queued download/);
  await fails(15, {operation: "runtime-read-download", buffer: partial.buffer, lease: 6}, /not synchronized/);
  await run(16, {operation: "runtime-synchronize"});
  await run(17, {operation: "runtime-read-download", buffer: partial.buffer, lease: 7});
  assert.deepEqual(Array.from(new Uint32Array(heap.buffer, 60, 1)), [23]);
  const partialDeviceBuffer = options.gpuRuntime.buffers.get(partial.buffer).buffer;
  await run(18, {operation: "runtime-destroy-buffer", buffer: partial.buffer});
  assert.equal(partialDeviceBuffer.destroyed, true);
  assert.deepEqual(released, [1, 3, 2, 8, 5, 6, 7]);

  // A failed operation releases its lease too: the Lua side only releases
  // after a successful answer, and the slots are few.
  const failed = await handleBrowserEffects({
    kind: "effects",
    requests: [{id: 19, kind: "gpu", operation: "runtime-upload", buffer: 999, lease: 4}],
  }, options);
  assert.equal(failed.responses[0].ok, false);
  assert.match(failed.responses[0].error, /buffer handle is unknown/);
  assert.deepEqual(released, [1, 3, 2, 8, 5, 6, 7, 4]);

  const queued = await run(21, {operation: "runtime-create-buffer", bytes: 4});
  await run(22, {operation: "runtime-enqueue-download", buffer: queued.buffer, offset: 0, bytes: 4});
  const queuedResource = options.gpuRuntime.buffers.get(queued.buffer);
  const queuedReadback = queuedResource.download.buffer;
  await fails(23, {operation: "runtime-close", buffers: false, kernels: []}, /resource lists are invalid/);
  const inputDeviceBuffer = options.gpuRuntime.buffers.get(input.buffer).buffer;
  const outputDeviceBuffer = options.gpuRuntime.buffers.get(output.buffer).buffer;
  await fails(24, {operation: "runtime-close", buffers: [input.buffer, -1], kernels: []}, /must be a uint32/);
  assert.equal(inputDeviceBuffer.destroyed, false);
  await run(25, {
    operation: "runtime-close",
    buffers: [input.buffer, output.buffer, partial.buffer, queued.buffer],
    kernels: [kernel.kernel],
  });
  assert.equal(inputDeviceBuffer.destroyed, true);
  assert.equal(outputDeviceBuffer.destroyed, true);
  assert.equal(queuedResource.buffer.destroyed, true);
  assert.equal(queuedReadback.destroyed, true);
  assert.equal(options.gpuRuntime.buffers.size, 0);
  assert.equal(options.gpuRuntime.kernels.size, 0);
});

// A device that keeps WebGPU's error scopes and limits, and reports a usage conflict
// the way WebGPU does: asynchronously, through whichever scope is open.
function scopedGpuDevice() {
  const scopes = [];
  const listeners = [];
  const device = {
    submitted: 0,
    limits: {maxComputeWorkgroupsPerDimension: 4},
    lost: {then() {}},
    addEventListener(type, listener) { if (type === "uncapturederror") listeners.push(listener); },
    raise(message) {
      const scope = [...scopes].reverse().find((entry) => entry.filter === "validation");
      if (scope) scope.error ||= {message};
      else for (const listener of listeners) listener({error: {message}});
    },
    pushErrorScope(filter) { scopes.push({filter, error: null}); },
    popErrorScope() { return Promise.resolve(scopes.pop().error); },
    queue: {writeBuffer() {}, submit() { device.submitted += 1; }, async onSubmittedWorkDone() {}},
    createShaderModule: () => ({}),
    createComputePipelineAsync: async () => ({getBindGroupLayout: () => ({})}),
    createBuffer: ({size}) => ({size, destroy() {}}),
    createBindGroup({entries}) {
      const buffers = entries.map((entry) => entry.resource.buffer);
      if (new Set(buffers).size !== buffers.length) {
        device.raise("Writable storage buffer binding aliasing found");
      }
      return {entries};
    },
    dispatches: [],
    createCommandEncoder() {
      const pass = {
        setPipeline() {}, setBindGroup() {}, end() {},
        dispatchWorkgroups(x, y = 1, z = 1) { device.dispatches.push([x, y, z]); },
      };
      return {beginComputePass: () => pass, finish: () => ({})};
    },
  };
  const options = {
    gpu: {requestAdapter: async () => ({requestDevice: async () => device})},
    GPUBufferUsage: {STORAGE: 1, COPY_DST: 2, COPY_SRC: 4, UNIFORM: 8, MAP_READ: 16},
    GPUMapMode: {READ: 1},
    transfers: {lease: () => ({view: new Uint8Array(16), bytes: 16}), release() {}},
  };
  let id = 0;
  const perform = async (operation) => {
    const result = await handleBrowserEffects({kind: "effects", requests: [{id: ++id, kind: "gpu", ...operation}]}, options);
    return result.responses[0];
  };
  return {device, perform};
}

test("the browser GPU host folds a long dispatch into rows and refuses past the last", async () => {
  const {device, perform} = scopedGpuDevice();
  const input = (await perform({operation: "runtime-create-buffer", bytes: 64})).value.buffer;
  const output = (await perform({operation: "runtime-create-buffer", bytes: 64})).value.buffer;
  const kernel = (await perform({
    operation: "runtime-compile", wgsl: "fn main() {}", entrypoint: "main",
    readonly: 1, writable: 1, uniformBytes: 20, threads: 2,
  })).value.kernel;
  const dispatch = (count) => perform({
    operation: "runtime-dispatch", kernel, read: [input], write: [output], count, lease: 1,
  });
  // A device holds four workgroups along a dimension here, of two lanes each.
  assert.equal((await dispatch(8)).ok, true, "four groups of two fit one row");
  assert.equal((await dispatch(9)).ok, true, "a fifth group starts a second row");
  assert.equal((await dispatch(32)).ok, true, "four full rows fit the limit");
  assert.deepEqual(device.dispatches, [[4, 1, 1], [4, 2, 1], [4, 4, 1]]);
  const submitted = device.submitted;
  const refused = await dispatch(33);
  assert.equal(refused.ok, false, "a dispatch WebGPU would drop was answered as done");
  // The native provider's wording, so a program sees one refusal on both targets.
  assert.equal(refused.error, "GPU dispatch workgroup count [4, 5, 1] exceeds the per-dimension limit 4");
  assert.equal(device.submitted, submitted, "the refused dispatch was submitted");
});

test("the browser GPU host surfaces validation errors instead of reporting success", async () => {
  const {device, perform} = scopedGpuDevice();
  const buffer = (await perform({operation: "runtime-create-buffer", bytes: 64})).value.buffer;
  const kernel = (await perform({
    operation: "runtime-compile", wgsl: "fn main() {}", entrypoint: "main",
    readonly: 1, writable: 1, uniformBytes: 20, threads: 1,
  })).value.kernel;
  const aliased = await perform({
    operation: "runtime-dispatch", kernel, read: [buffer], write: [buffer], count: 1, lease: 1,
  });
  assert.equal(aliased.ok, false, "an aliased dispatch was answered as done");
  assert.match(aliased.error, /WebGPU validation failed: Writable storage buffer binding aliasing/);

  // An error no scope caught still reaches the program, at its next operation.
  device.raise("the device saw something wrong");
  const next = await perform({operation: "runtime-synchronize"});
  assert.equal(next.ok, false);
  assert.match(next.error, /WebGPU device error: the device saw something wrong/);
  assert.equal((await perform({operation: "runtime-synchronize"})).ok, true, "one error is reported once");
});

test("browser effect quotas fail before host work begins", async () => {
  const requests = Array.from({length: 3}, (_, index) => ({
    id: index + 1, kind: "time", operation: "now",
  }));
  await assert.rejects(
    handleBrowserEffects({kind: "effects", requests}, {limitOverrides: {maxEffects: 2}}),
    /more than 2 effects/,
  );
});

// One lane, standing in for a module Web Worker that boots the payload. It answers
// the pool's protocol so the page-side half can be exercised without Wasm.
class FakeLane {
  static opened = [];

  constructor(url, options) {
    this.url = url;
    this.options = options;
    this.listeners = new Map();
    this.posted = [];
    this.running = undefined;
    this.terminated = false;
    FakeLane.opened.push(this);
  }

  addEventListener(name, handler) {
    this.listeners.set(name, [...(this.listeners.get(name) || []), handler]);
  }

  emit(name, event) {
    for (const handler of this.listeners.get(name) || []) handler(event);
  }

  postMessage(message) {
    this.posted.push(message);
    if (message.type === "task") {
      this.running = message.task;
      this.emit("message", {data: {type: "started", id: message.task.id}});
    }
    if (message.type === "cancel" && this.running?.id === message.id) {
      const id = message.id;
      this.running = undefined;
      this.emit("message", {data: {type: "reply", id, status: "cancelled", deadline: message.deadline}});
    }
  }

  finish(status, extra = {}) {
    const id = this.running.id;
    this.running = undefined;
    this.emit("message", {data: {type: "reply", id, status, ...extra}});
  }

  terminate() {
    this.terminated = true;
  }
}

function pool(overrides = {}) {
  FakeLane.opened = [];
  return createWorkerPool({
    laneUrl: "https://example.test/worker-lane.mjs",
    manifestUrl: "https://example.test/nupp-browser-app.json",
    manifestDigest: "a".repeat(64),
    maxLanes: 2,
    WorkerClass: FakeLane,
    ...overrides,
  });
}

function submission(id, overrides = {}) {
  return {
    operation: "submit",
    tasks: [{task: id, module: "jobs", member: "hash", payload: "AA==", ...overrides}],
  };
}

test("a worker pool boots at most its lane bound and reuses idle lanes", async () => {
  const workers = pool();
  // One message however many children it carries, which is what a scope that
  // submits a list before awaiting any of it produces.
  assert.equal(workers.perform({
    operation: "submit",
    tasks: [1, 2, 3].map((id) => ({task: id, module: "jobs", member: "hash", payload: "AA=="})),
  }).lanes, 2);
  assert.equal(FakeLane.opened.length, 2, "the third task queues rather than opening a lane");
  for (const lane of FakeLane.opened) {
    assert.equal(lane.options.type, "module");
    assert.deepEqual(lane.posted[0], {
      type: "boot",
      manifestUrl: "https://example.test/nupp-browser-app.json",
      manifestDigest: "a".repeat(64),
      entry: "nupp.workers",
      limits: undefined,
    });
  }
  FakeLane.opened[0].finish("done", {payload: "Zg=="});
  assert.equal(FakeLane.opened[0].running.id, 3, "the freed lane takes the queued task");
  assert.deepEqual(await workers.perform({operation: "await", task: 1}), {
    status: "done", payload: "Zg==", started: [3],
  });
  workers.close();
});

test("a worker pool needs the digest of the manifest its page verified", () => {
  assert.throws(() => pool({manifestDigest: undefined}), /manifest digest/);
});

test("a worker lane refuses a manifest other than the one its page verified", async (t) => {
  // A deploy between page load and lane start: the lane's fetch of the same URL
  // answers with the next build's manifest.
  const deployed = new TextEncoder().encode(JSON.stringify({
    schema: 1, runtime: "luajit-v86", app: "app-next.lua", guest: "guest/next/guest-manifest.json",
    assets: {"app-next.lua": {bytes: 1, sha256: "b".repeat(64)}},
  }));
  const fetched = [];
  const saved = globalThis.fetch;
  globalThis.fetch = async (url) => {
    fetched.push(String(url));
    return String(url).endsWith("/nupp-browser-app.json")
      ? new Response(deployed)
      : new Response("missing", {status: 404});
  };
  t.after(() => { globalThis.fetch = saved; });
  await assert.rejects(
    runPackagedNuppLuaJITApp("https://example.test/nupp-browser-app.json", {manifestDigest: "a".repeat(64)}),
    /manifest changed after the page loaded it/,
  );
  assert.deepEqual(fetched, ["https://example.test/nupp-browser-app.json"], "no asset of the other build is fetched");
});

test("a worker pool carries results, failures and cancellations back unchanged", async () => {
  const workers = pool({maxLanes: 1});
  workers.perform(submission(1));
  FakeLane.opened[0].finish("failed", {error: "cannot hash beta"});
  assert.deepEqual(await workers.perform({operation: "await", task: 1}), {
    status: "failed", error: "cannot hash beta", started: [],
  });
  workers.perform(submission(2));
  workers.perform({operation: "cancel", task: 2});
  const cancelled = await workers.perform({operation: "await", task: 2});
  assert.equal(cancelled.status, "cancelled");
  workers.close();
});

test("a worker pool settles a queued cancellation without invoking its function", async () => {
  const workers = pool({maxLanes: 1});
  workers.perform(submission(1));
  workers.perform(submission(2));
  workers.perform({operation: "cancel", task: 2});
  assert.deepEqual(await workers.perform({operation: "await", task: 2}), {
    status: "cancelled", deadline: false, started: [],
  });
  assert.equal(FakeLane.opened[0].posted.filter((message) => message.type === "task").length, 1);
  workers.close();
});

test("a worker pool fails the task a dying lane was running", async () => {
  const workers = pool({maxLanes: 1});
  workers.perform(submission(1));
  FakeLane.opened[0].emit("error", {message: "lane crashed"});
  const failure = await workers.perform({operation: "await", task: 1});
  assert.equal(failure.status, "failed");
  assert.match(failure.error, /a worker lane ended before answering a task: lane crashed/);
  assert.equal(FakeLane.opened[0].terminated, true);
  workers.perform(submission(2));
  assert.equal(FakeLane.opened.length, 2, "a replacement lane takes later work");
  workers.close();
});

test("a worker pool ignores stale replies without reassigning a busy lane", async () => {
  const workers = pool({maxLanes: 1});
  workers.perform({
    operation: "submit",
    tasks: [1, 2, 3].map((id) => ({task: id, module: "jobs", member: "hash", payload: "AA=="})),
  });
  const lane = FakeLane.opened[0];
  lane.finish("done", {payload: "AQ=="});
  assert.equal(lane.running.id, 2);

  lane.emit("message", {data: {type: "reply", id: 1, status: "done", payload: "stale"}});
  assert.equal(lane.running.id, 2, "a duplicate reply leaves the current assignment intact");
  assert.equal(lane.posted.filter((message) => message.type === "task").length, 2);

  lane.finish("done", {payload: "Ag=="});
  assert.equal(lane.running.id, 3);
  lane.finish("done", {payload: "Aw=="});
  assert.equal((await workers.perform({operation: "await", task: 1})).payload, "AQ==");
  assert.equal((await workers.perform({operation: "await", task: 2})).payload, "Ag==");
  assert.equal((await workers.perform({operation: "await", task: 3})).payload, "Aw==");
  workers.close();
});

test("a worker pool turns malformed lane replies into task failures", async () => {
  const workers = pool({maxLanes: 1});
  workers.perform(submission(1));
  FakeLane.opened[0].emit("message", {
    data: {type: "reply", id: 1, status: "done", payload: 7},
  });
  const failure = await workers.perform({operation: "await", task: 1});
  assert.equal(failure.status, "failed");
  assert.match(failure.error, /invalid task reply/);
  workers.close();
});

test("a worker pool refuses submissions it cannot frame", () => {
  const workers = pool();
  assert.deepEqual(workers.perform(submission(1, {payload: 7})).rejected, [
    {task: 1, error: "invalid browser worker submission"},
  ]);
  for (const id of [0, Number.MAX_SAFE_INTEGER + 1]) {
    assert.deepEqual(workers.perform(submission(id)).rejected, [
      {task: id, error: "invalid browser worker submission"},
    ]);
  }
  workers.perform(submission(1));
  assert.deepEqual(workers.perform(submission(1)).rejected, [
    {task: 1, error: "a browser worker task id was reused"},
  ]);
  assert.throws(() => workers.perform({operation: "sleep"}), /unsupported browser worker operation/);
  workers.close();
  assert.throws(() => workers.perform(submission(2)), /pool is closed/);
});

test("closing a worker pool fails everything still outstanding", async () => {
  const workers = pool();
  workers.perform(submission(1));
  workers.close();
  assert.match((await workers.perform({operation: "await", task: 1})).error, /pool closed/);
  assert.ok(FakeLane.opened.every((lane) => lane.terminated));
});

test("HTTP moves response chunks through a writable transfer lease without base64", async () => {
  const heap = new Uint8Array(64);
  const leases = new Map([[1, {pointer: 8, bytes: 5}]]);
  let writable = true;
  const options = {
    transfers: heapTransfers(heap, leases, [], () => writable),
    fetch: async () => new Response(Uint8Array.of(0, 255, 65, 66, 67), {status: 200}),
  };
  const request = {kind: "effects", requests: [{id: 1, kind: "http", url: "https://example.test", memoryResponse: true}]};
  let result = (await handleBrowserEffects(request, options)).responses[0];
  assert.equal(result.ok, true);
  assert.equal(result.value.bodyBytes, 5);
  assert.equal(result.value.bodyBase64, undefined);
  const body = result.value.body;
  result = (await handleBrowserEffects({kind: "effects", requests: [{id: 2, kind: "http", operation: "read-body", body, lease: 1}]}, options)).responses[0];
  assert.equal(result.ok, true, result.error);
  assert.deepEqual(Array.from(heap.subarray(8, 13)), [0, 255, 65, 66, 67]);
  assert.equal(leases.has(1), false);
  assert.equal(options.httpBodies.size, 0);

  leases.set(1, {pointer: 8, bytes: 5});
  result = (await handleBrowserEffects(request, options)).responses[0];
  const orphan = result.value.body;
  assert.equal(options.httpBodies.has(orphan), true);
  result = (await handleBrowserEffects({kind: "effects", requests: [{
    id: 4, kind: "http", operation: "release-body", body: orphan,
  }]}, options)).responses[0];
  assert.deepEqual(result.value, {released: true});
  assert.equal(options.httpBodies.size, 0);

  writable = false;
  result = (await handleBrowserEffects(request, options)).responses[0];
  result = (await handleBrowserEffects({kind: "effects", requests: [{id: 3, kind: "http", operation: "read-body", body: result.value.body, lease: 1}]}, options)).responses[0];
  assert.equal(result.ok, false);
  assert.match(result.error, /writable/);
  assert.equal(leases.has(1), false);
  assert.equal(options.httpBodies.size, 0);
});
