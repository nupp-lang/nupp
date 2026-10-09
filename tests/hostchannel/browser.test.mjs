// The host channel's contract, end to end in the browser runtime's shape.
//
// The application runs in `guest.lua`, which reproduces the bridge's treatment
// of every frame, and the page here is the real dispatcher in
// `runtime/wasm/app-runtime.mjs` with the transfer table the LuaJIT runtime
// builds. Only the emulator is missing, which is what lets this run anywhere
// Node and LuaJIT do.
//
// NUPP_ROOT names the checkout and LUA_PATH/LUA_CPATH the compiled runtime; the
// Lua suite `tests/hostchanneltest.lua` sets them.

import test from "node:test";
import assert from "node:assert/strict";
import {spawn} from "node:child_process";
import {createInterface} from "node:readline";
import {createTransfers} from "../../runtime/luajit/transfers.mjs";
import {closeHostChannel, handleBrowserEffects} from "../../runtime/wasm/app-runtime.mjs";

const ROOT = process.env.NUPP_ROOT || new URL("../..", import.meta.url).pathname;
const LUAJIT = process.env.NUPP_LUAJIT || "luajit";
const GUEST = new URL("./guest.lua", import.meta.url).pathname;
const SCENARIOS = new URL("./scenarios.lua", import.meta.url).pathname;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function pattern(size, seed) {
  const bytes = new Uint8Array(size);
  for (let index = 0; index < size; index++) bytes[index] = (index * 31 + seed) % 251;
  return bytes;
}

function sum(bytes) {
  let total = 0;
  for (let index = 0; index < bytes.length; index++) total = (total + bytes[index] * (index % 7 + 1)) % 2147483647;
  return total;
}

/** A page whose handlers record what they saw and own countable resources. */
function testHost() {
  const seen = new Map();
  const live = new Set();
  const released = [];
  const notes = [];
  let nextResource = 1;
  let ended = 0;
  const note = (kind) => seen.set(kind, (seen.get(kind) || 0) + 1);
  const handlers = {
    "test.echo": (args) => { note("test.echo"); return args; },
    "test.results": () => [null, 2, null],
    "test.fail": ([why]) => { throw new Error(`failed because ${why}`); },
    "test.digest": ([bytes]) => [bytes.length, sum(bytes), bytes],
    "test.count": (args) => { note("test.count"); return args.reduce((total, bytes) => total + bytes.length, 0); },
    "test.make": ([size, seed]) => pattern(size, seed),
    "test.makeMany": {
      call: ([count, size]) => {
        const id = nextResource++;
        live.add(id);
        return [id, ...Array.from({length: count}, (_, index) => pattern(size, index))];
      },
      release: ([id]) => { live.delete(id); released.push(id); },
    },
    "test.resource": {
      call: ([size]) => {
        const id = nextResource++;
        live.add(id);
        return [id, pattern(size, 4)];
      },
      release: ([id]) => { live.delete(id); released.push(id); },
    },
    "test.slow": async ([bytes, ms]) => { await sleep(ms); return bytes.length; },
    "test.open": async ([ms]) => {
      await sleep(ms);
      const id = nextResource++;
      live.add(id);
      return id;
    },
    "test.close": ([id]) => { live.delete(id); },
    "test.live": () => live.size,
    "test.seen": ([kind]) => seen.get(kind) || 0,
    "test.note": ([index, bytes]) => { notes.push(`${index}:${bytes.length}`); },
    "test.notes": () => notes.join(","),
  };
  return {
    host: {handlers, end: () => { ended++; }, onError: () => {}},
    state: {seen, live, released, get ended() { return ended; }},
  };
}

async function runGuest(name, host) {
  const child = spawn(LUAJIT, [GUEST, ROOT, SCENARIOS, name], {stdio: ["pipe", "pipe", "pipe"], env: process.env});
  let stderr = "";
  child.stderr.on("data", (data) => { stderr += data; });
  const lines = createInterface({input: child.stdout, crlfDelay: Infinity})[Symbol.asyncIterator]();
  // The emulator's clock is wall time, where the guest bridge reads the page's
  // performance clock; deadlines must be measured on the one the guest uses.
  const options = {host, performance: {now: () => Date.now()}};
  let frames = 0;
  try {
    while (true) {
      const next = await lines.next();
      if (next.done) throw new Error(`the guest exited without an answer:\n${stderr}`);
      const message = JSON.parse(next.value);
      if (message.type === "done") {
        closeHostChannel(options);
        return {...message, frames, stderr};
      }
      frames++;
      const payload = Buffer.from(message.payload || "", "base64");
      const frame = message.frame;
      const transfers = createTransfers(frame._leases, payload.buffer.slice(payload.byteOffset, payload.byteOffset + payload.length));
      delete frame._leases;
      options.transfers = transfers;
      const response = await handleBrowserEffects(frame, options);
      const returned = transfers.response();
      response._leases = returned.leases;
      const text = JSON.stringify(response);
      assert.ok(text.length <= 1024 * 1024, `answer text of ${text.length} bytes exceeds the guest's slot`);
      child.stdin.write(JSON.stringify({response, payload: Buffer.from(returned.payload).toString("base64")}) + "\n");
    }
  } finally {
    child.stdin.end();
    child.kill();
  }
}

async function scenario(name) {
  const {host, state} = testHost();
  const outcome = await runGuest(name, host);
  assert.equal(outcome.ok, true, `${name} failed:\n${outcome.error}\n${outcome.stderr}`);
  assert.equal(outcome.leases, 0, `${name} left guest leases outstanding`);
  return {value: outcome.value, state, outcome};
}

test("every position is kept, interior and trailing nil included", async () => {
  const {value} = await scenario("arity");
  assert.deepEqual(value.echoed, {n: 5, a: 1, c: "two", d: true});
  assert.equal(value.none, 0);
  assert.equal(value.onlyNil, 1);
  assert.deepEqual(value.interior, {n: 3, b: 2});
});

test("values that cannot cross are refused with their position", async () => {
  const {value} = await scenario("refusals");
  assert.match(value.nan, /argument 1 is not a finite number/);
  assert.match(value.infinity, /argument 2 is not a finite number/);
  assert.match(value.text, /argument 1 is a string that is not UTF-8/);
  assert.match(value.long, /argument 1 is a string longer than 64 KiB/);
  assert.match(value.table, /argument 1 is a table, which cannot cross/);
  assert.match(value.handler, /argument 1 is a function, which cannot cross/);
  assert.match(value.reserved, /reserved for the runtime/);
  assert.match(value.kind, /must be dot-separated names/);
  assert.match(value.unknown, /no host answers test\.nobody/);
  assert.match(value.failed, /host test\.fail failed: failed because why/);
});

test("bytes cross in both directions, chunked past one MiB", async () => {
  const {value} = await scenario("bytes");
  assert.deepEqual(value, {small: true, large: true, three: true, made: true, empty: true});
});

test("a slow call carrying bytes does not hold a deadline beside it", async () => {
  const {value} = await scenario("slowCallBesideADeadline");
  assert.equal(value.slow, 4096);
  assert.ok(value.firedAfter >= 50 && value.firedAfter < 400, `the deadline fired after ${value.firedAfter} ms`);
});

test("late releases what an abandoned call opened", async () => {
  const {value, state} = await scenario("lateReleases");
  assert.match(value.cancelled, /deadline/);
  assert.equal(value.live, 0);
  assert.equal(state.live.size, 0);
});

test("late cannot wait, and other deliveries carry on", async () => {
  const {value, outcome} = await scenario("lateCannotWait");
  assert.equal(value.echoed, "still answering");
  assert.equal(value.live, 1, "the refused late handler did not release");
  assert.match(outcome.stderr, /late handler failed: .*cannot suspend/);
});

test("a request cancelled before it shipped never reaches the page", async () => {
  const {value} = await scenario("cancelBeforeShipping");
  assert.equal(value.cancelled, true);
  assert.equal(value.seen, 0);
});

test("a result abandoned mid-fetch is released by the page, not late", async () => {
  const {value, state} = await scenario("cancelMidFetch");
  assert.equal(value.cancelled, true);
  assert.equal(value.live, 0);
  assert.equal(state.released.length, 1);
  assert.equal(value.after, 16 * 1024 * 1024, "the reassembly budget came back whole");
});

test("results filling the budget are admitted in turn, and an oversized one is refused", async () => {
  const {value, state} = await scenario("concurrentLargeResults");
  assert.deepEqual(value.sizes, [16 * 1024 * 1024, 16 * 1024 * 1024, 16 * 1024 * 1024, 16 * 1024 * 1024]);
  assert.match(value.tooLarge, /more than the 16 MiB a result may hold/);
  assert.equal(value.live, 0);
  assert.equal(state.released.length, 1);
});

test("more requests than a frame carries all ship and all answer", async () => {
  const {value, outcome} = await scenario("manySmallCalls");
  assert.equal(value.correct, 600);
  assert.ok(outcome.frames > 2, "the requests were packed into more than one frame");
});

test("posts ship without waiting, and the session ends once", async () => {
  const {value, state} = await scenario("posts");
  assert.equal(value.notes, "1:100,2:100,3:100,4:100,5:100,6:100,7:100,8:100,9:100,10:100");
  assert.equal(state.ended, 1);
});
