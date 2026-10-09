// The page's answers to the contract scenarios and the benchmark workloads,
// shared by the real-guest page and anything else that hosts them.

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export function pattern(size, seed) {
  const bytes = new Uint8Array(size);
  for (let index = 0; index < size; index++) bytes[index] = (index * 31 + seed) % 251;
  return bytes;
}

export function sum(bytes) {
  let total = 0;
  for (let index = 0; index < bytes.length; index++) total = (total + bytes[index] * (index % 7 + 1)) % 2147483647;
  return total;
}

/** Handlers whose resources and observations the caller can inspect. */
export function testHost() {
  const seen = new Map();
  const live = new Set();
  const released = [];
  const notes = [];
  const outbound = [];
  let push = null;
  const packets = [];
  let nextResource = 1;
  let ended = 0;
  const note = (kind) => seen.set(kind, (seen.get(kind) || 0) + 1);
  const handlers = {
    "test.echo": (args) => { note("test.echo"); return args; },
    "test.ping": () => 1,
    "test.results": () => [null, 2, null],
    "test.fail": ([why]) => { throw new Error(`failed because ${why}`); },
    "test.digest": ([bytes]) => [bytes.length, sum(bytes), bytes],
    "test.len": ([bytes]) => bytes.length,
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
    "test.pushInput": ([count]) => {
      for (let index = 1; index <= count; index++) push("test.move", index, index * 10);
      push("test.key", "a", true);
      push("test.key", "b", false);
    },
    "test.packet": ([bytes]) => { outbound.push(`packet:${bytes.length}`); },
    "test.log": ([text]) => { outbound.push(`log:${text}`); },
    "test.block": ([text]) => { outbound.push(`block:${text}`); },
    "test.outbound": () => outbound.join(" "),
    // Workloads: a frame's input arrives as one call, its packet leaves as a post.
    "bench.input": ([count]) => {
      const values = [];
      for (let index = 0; index < count; index++) values.push(index * 1.5, index * 0.5);
      return [count, ...values.slice(0, 200)];
    },
    "bench.packet": ([bytes]) => { packets.push(bytes.length); },
  };
  return {
    host: {handlers, start: (api) => { push = api.push; }, end: () => { ended++; }, onError: () => {}},
    state: {seen, live, released, packets, get ended() { return ended; }},
  };
}
