import assert from "node:assert/strict";
import { createHash, webcrypto } from "node:crypto";
import test from "node:test";

import {
  handleBrowserEffects,
  runPackagedNuppWasmApp,
} from "../../runtime/wasm/app-runtime.mjs";
import { runtimeSourceDigest } from "../../runtime/wasm/build-runtime-package.mjs";
import { createWorkerPool } from "../../runtime/wasm/worker-pool.mjs";

globalThis.crypto ||= webcrypto;

const bytes = new TextEncoder().encode("fixture");
const checksum = createHash("sha256").update(bytes).digest("hex");
const moduleChecksum = "1".repeat(64);

function manifest(overrides = {}) {
  return {
    schemaVersion: 1,
    target: "wasm32-unknown-emscripten",
    runtime: {
      module: {file: `nupp-app-${moduleChecksum.slice(0, 16)}.mjs`, sha256: moduleChecksum, bytes: 1},
      wasm: {file: "nupp-app.wasm", sha256: checksum, bytes: bytes.length},
    },
    app: {file: "app.lua", sha256: checksum, bytes: bytes.length},
    sideModules: [],
    ...overrides,
  };
}

function fetcher(document) {
  return async (url) => {
    if (String(url).endsWith("nupp-browser-app.json")) {
      return new Response(JSON.stringify(document), {status: 200});
    }
    return new Response(bytes, {status: 200});
  };
}

test("packaged applications reject unknown manifest versions", async () => {
  await assert.rejects(
    runPackagedNuppWasmApp("https://example.test/nupp-browser-app.json", {
      fetch: fetcher({...manifest(), schemaVersion: 99}),
    }),
    /unsupported Nupp browser application manifest/,
  );
});

test("packaged application assets cannot escape their directory", async () => {
  await assert.rejects(
    runPackagedNuppWasmApp("https://example.test/nupp-browser-app.json", {
      fetch: fetcher(manifest({app: {file: "../app.lua", sha256: checksum, bytes: bytes.length}})),
    }),
    /app\.file must stay inside/,
  );
});

test("packaged applications verify fetched bytes", async () => {
  await assert.rejects(
    runPackagedNuppWasmApp("https://example.test/nupp-browser-app.json", {
      fetch: fetcher(manifest({app: {file: "app.lua", sha256: "2".repeat(64), bytes: bytes.length}})),
    }),
    /app SHA-256 mismatch/,
  );
});

test("runtime modules use content-addressed filenames", async () => {
  const runtime = manifest().runtime;
  runtime.module.file = "nupp-app.mjs";
  await assert.rejects(
    runPackagedNuppWasmApp("https://example.test/nupp-browser-app.json", {
      fetch: fetcher(manifest({runtime})),
    }),
    /runtime\.module must use its content-addressed filename/,
  );
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

test("browser storage effects preserve values through the provider contract", async () => {
  const values = new Map();
  const storage = {
    get: async (key) => values.get(key),
    set: async (key, value) => values.set(key, value),
    remove: async (key) => values.delete(key),
    clear: async () => values.clear(),
  };
  const run = (requests) => handleBrowserEffects({kind: "effects", requests}, {storage});
  await run([{id: 1, kind: "storage", operation: "set", key: "answer", value: "42"}]);
  const found = await run([{id: 2, kind: "storage", operation: "get", key: "answer"}]);
  assert.deepEqual(found.responses[0], {id: 2, ok: true, value: {found: true, value: "42"}});
  await run([{id: 3, kind: "storage", operation: "remove", key: "answer"}]);
  const missing = await run([{id: 4, kind: "storage", operation: "get", key: "answer"}]);
  assert.deepEqual(missing.responses[0], {id: 4, ok: true, value: {found: false}});
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

test("runtime source digests cover the reusable host inputs", () => {
  assert.match(runtimeSourceDigest(), /^[0-9a-f]{64}$/);
  assert.equal(runtimeSourceDigest(), runtimeSourceDigest());
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
    assert.equal(lane.posted[0].type, "boot");
    assert.equal(lane.posted[0].entry, "nupp.workers");
  }
  FakeLane.opened[0].finish("done", {payload: "Zg=="});
  assert.equal(FakeLane.opened[0].running.id, 3, "the freed lane takes the queued task");
  assert.deepEqual(await workers.perform({operation: "await", task: 1}), {
    status: "done", payload: "Zg==", started: [3],
  });
  workers.close();
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

test("a worker pool refuses submissions it cannot frame", () => {
  const workers = pool();
  assert.deepEqual(workers.perform(submission(1, {payload: 7})).rejected, [
    {task: 1, error: "invalid browser worker submission"},
  ]);
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
