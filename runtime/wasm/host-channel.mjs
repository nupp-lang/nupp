// The page's side of `nupp.host`: requests a Nupp application makes of the page
// that runs it, answered by handlers the page registers by kind.
//
// A handler receives the request's values as an array, one slot per position,
// and answers with an array of results (or `undefined` for none). Values are
// `null`, booleans, finite numbers, strings and bytes (`Uint8Array`, or any
// `ArrayBuffer` view). A handler may be a function, or an object with `call` and
// `release`: `release(results)` runs for results the application never came to
// own, such as a result whose bytes it stopped fetching when its caller was
// cancelled, so a host resource named in a result is always released by
// someone. `end()` runs once the application has finished.
//
// Streams carry messages one way. A handler receives the application's sent
// messages as it does a call, and its answer is ignored. `start({push})` runs
// when the channel opens and hands the page `push(kind, ...values)`, which
// queues an inbound message for the next frame the application takes; an
// inbound message carries scalars and strings only, which is what an event's
// fields hold.
//
// The application's traffic arrives once a frame as binary records in a read
// lease (the format is `src/nupp/runtime/browser/hostwire.g.nupp`'s), and the
// page answers into the writable inbox the same frame lends, at the end of the
// frame, with whatever answers and messages are ready by then.

const MAX_STRING_BYTES = 64 * 1024;
const MAX_OUTBOUND_BYTES = 64 * 1024 * 1024;
const MAX_INBOUND_BYTES = 8 * 1024 * 1024;
// A byte result larger than this stays with the page to be fetched rather than
// riding the inbox, which every frame copies whole in both directions.
const INLINE_BYTES = 16 * 1024;
const MAX_VALUES = 255;
const DEFAULT_REASSEMBLY_BYTES = 128 * 1024 * 1024;
const MAX_INBOUND_MESSAGES = 4096;
const KIND = /^[\w-]+\.[\w.-]*[\w-]$/;
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", {fatal: true});

const OUT = {CALL: 1, POST: 2, SEND: 3, CANCEL: 4, ABANDON: 5, ABORT: 6, ROUTES: 7};
const IN = {ANSWER: 1, MESSAGE: 2, DROPPED: 3};
const TAG = {NIL: 0, FALSE: 1, TRUE: 2, NUMBER: 3, STRING: 4, BYTES: 5, UPLOAD: 6, FETCH: 7};

function checkedKind(name) {
  if (typeof name !== "string" || name.length > 128 || !KIND.test(name) || name.includes("..")) {
    throw new Error(`host kind ${JSON.stringify(name)} must be dot-separated names`);
  }
  if (name.startsWith("nupp.")) throw new Error(`host kind ${name} is reserved for the runtime`);
  return name;
}

function normalizedHandlers(handlers = {}) {
  if (typeof handlers !== "object" || handlers === null || Array.isArray(handlers)) {
    throw new Error("host handlers must be an object keyed by kind");
  }
  const normalized = new Map();
  for (const [name, handler] of Object.entries(handlers)) {
    checkedKind(name);
    if (typeof handler === "function") {
      normalized.set(name, {call: handler});
    } else if (handler && typeof handler.call === "function" &&
        (handler.release === undefined || typeof handler.release === "function")) {
      normalized.set(name, {call: handler.call.bind(handler), release: handler.release?.bind(handler)});
    } else {
      throw new Error(`host handler ${name} must be a function or an object with call`);
    }
  }
  return normalized;
}

/** Creates the per-run state of the host channel from the page's `host` option. */
export function createHostChannel(host = {}) {
  if (typeof host !== "object" || host === null) throw new Error("the host option must be an object");
  const reassemblyLimit = host.maxReassemblyBytes ?? DEFAULT_REASSEMBLY_BYTES;
  if (!Number.isSafeInteger(reassemblyLimit) || reassemblyLimit < 1) {
    throw new Error("host.maxReassemblyBytes must be a positive integer");
  }
  if (host.end !== undefined && typeof host.end !== "function") throw new Error("host.end must be a function");
  if (host.start !== undefined && typeof host.start !== "function") throw new Error("host.start must be a function");
  const channel = {
    handlers: normalizedHandlers(host.handlers),
    end: host.end,
    report: typeof host.onError === "function" ? host.onError : (error) => console.warn(error),
    reassemblyLimit,
    reassembled: 0,
    uploads: new Map(),
    results: new Map(),
    inflight: new Map(),
    answers: [],
    inbound: [],
    dropped: {},
    routes: {},
    frames: new Map(),
    notify: null,
    nextResult: 1,
    closed: false,
  };
  host.start?.({push: (kind, ...values) => pushMessage(channel, kind, values)});
  return channel;
}

function channelOf(options) {
  return options.hostChannel ||= createHostChannel(options.host);
}

function wake(channel) {
  const notify = channel.notify;
  channel.notify = null;
  notify?.();
}

function releaseResult(channel, record) {
  try {
    record.release?.(record.values);
  } catch (error) {
    channel.report(error);
  }
}

/** Ends the session: releases every result never taken, then tells the page. */
export function closeHostChannel(options) {
  const channel = options.hostChannel;
  if (!channel || channel.closed) return;
  channel.closed = true;
  for (const controller of channel.inflight.values()) controller.abort(new Error("the application finished"));
  channel.inflight.clear();
  for (const item of channel.answers) if (item.ok) releaseResult(channel, {release: item.release, values: item.results});
  channel.answers = [];
  for (const record of channel.results.values()) releaseResult(channel, record);
  channel.results.clear();
  channel.uploads.clear();
  channel.reassembled = 0;
  wake(channel);
  try {
    channel.end?.();
  } catch (error) {
    channel.report(error);
  }
}

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

function asBytes(value) {
  if (value instanceof Uint8Array) return value;
  if (ArrayBuffer.isView(value)) return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  if (value instanceof ArrayBuffer) return new Uint8Array(value);
  return null;
}

function checkedText(value, describe) {
  if (value.isWellFormed?.() === false) throw new Error(`${describe} is not valid text`);
  const bytes = encoder.encode(value);
  if (bytes.length > MAX_STRING_BYTES) throw new Error(`${describe} is a string longer than 64 KiB; answer bytes`);
  return bytes;
}

// Validates a handler's answer against the value model.
function checkedResults(name, answer) {
  const results = answer === undefined ? [] : Array.isArray(answer) ? answer : [answer];
  if (results.length > MAX_VALUES) throw new Error(`host handler ${name} answered more than 255 values`);
  return results.map((value, index) => {
    const describe = `host handler ${name} result ${index + 1}`;
    if (value === null || value === undefined) return {tag: TAG.NIL};
    const view = asBytes(value);
    if (view) {
      if (view.byteLength > MAX_INBOUND_BYTES) throw new Error(`${describe} is more than 8 MiB of bytes`);
      return {tag: TAG.BYTES, bytes: view};
    }
    if (typeof value === "boolean") return {tag: value ? TAG.TRUE : TAG.FALSE};
    if (typeof value === "number") {
      if (!Number.isFinite(value)) throw new Error(`${describe} is not a finite number`);
      return {tag: TAG.NUMBER, number: value};
    }
    if (typeof value === "string") return {tag: TAG.STRING, bytes: checkedText(value, describe)};
    throw new Error(`${describe} is a ${typeof value}, which cannot cross`);
  });
}

function inboundValue(kind, value, position) {
  const describe = `host push ${kind} value ${position}`;
  if (value === null || value === undefined) return {tag: TAG.NIL};
  if (typeof value === "boolean") return {tag: value ? TAG.TRUE : TAG.FALSE};
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error(`${describe} is not a finite number`);
    return {tag: TAG.NUMBER, number: value};
  }
  if (typeof value === "string") return {tag: TAG.STRING, bytes: checkedText(value, describe)};
  throw new Error(`${describe} is a ${typeof value}; an inbound message carries scalars and strings`);
}

// ---------------------------------------------------------------------------
// The binary records
// ---------------------------------------------------------------------------

class Reader {
  constructor(bytes) {
    this.buffer = bytes;
    this.view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    this.at = 0;
  }
  take(count) {
    const at = this.at;
    if (at + count > this.buffer.length) throw new Error("a host frame's records ended inside a record");
    this.at = at + count;
    return at;
  }
  u8() { return this.view.getUint8(this.take(1)); }
  u16() { return this.view.getUint16(this.take(2), true); }
  u32() { return this.view.getUint32(this.take(4), true); }
  f64() { return this.view.getFloat64(this.take(8), true); }
  bytes(count) { const at = this.take(count); return this.buffer.slice(at, at + count); }
  text(count) { const at = this.take(count); return decoder.decode(this.buffer.subarray(at, at + count)); }
  get remaining() { return this.buffer.length - this.at; }
}

class Writer {
  constructor(capacity = 256) {
    this.buffer = new Uint8Array(capacity);
    this.view = new DataView(this.buffer.buffer);
    this.length = 0;
  }
  reserve(count) {
    const needed = this.length + count;
    if (needed > this.buffer.length) {
      const grown = new Uint8Array(Math.max(needed, this.buffer.length * 2));
      grown.set(this.buffer.subarray(0, this.length));
      this.buffer = grown;
      this.view = new DataView(grown.buffer);
    }
    const at = this.length;
    this.length = needed;
    return at;
  }
  // Reserve before reading `buffer` or `view`: growing replaces both.
  u8(value) { const at = this.reserve(1); this.view.setUint8(at, value); }
  u16(value) { const at = this.reserve(2); this.view.setUint16(at, value, true); }
  u32(value) { const at = this.reserve(4); this.view.setUint32(at, value, true); }
  f64(value) { const at = this.reserve(8); this.view.setFloat64(at, value, true); }
  raw(bytes) { const at = this.reserve(bytes.length); this.buffer.set(bytes, at); }
  sized(bytes) { this.u32(bytes.length); this.raw(bytes); }
  result() { return this.buffer.subarray(0, this.length); }
}

function readArguments(channel, reader) {
  const count = reader.u16();
  if (count > MAX_VALUES) throw new Error("a host request carries more than 255 values");
  const args = new Array(count);
  for (let index = 0; index < count; index++) {
    const tag = reader.u8();
    if (tag === TAG.NIL) args[index] = null;
    else if (tag === TAG.FALSE) args[index] = false;
    else if (tag === TAG.TRUE) args[index] = true;
    else if (tag === TAG.NUMBER) args[index] = reader.f64();
    else if (tag === TAG.STRING) args[index] = reader.text(reader.u32());
    else if (tag === TAG.BYTES) args[index] = reader.bytes(reader.u32());
    else if (tag === TAG.UPLOAD) {
      const transfer = reader.u32();
      const upload = channel.uploads.get(transfer);
      if (!upload || upload.received !== upload.total) {
        throw new Error(`host request value ${index + 1} names an incomplete upload`);
      }
      channel.uploads.delete(transfer);
      channel.reassembled -= upload.total;
      args[index] = upload.bytes;
    } else {
      throw new Error(`host request value ${index + 1} has an unknown tag ${tag}`);
    }
  }
  return args;
}

function writeValue(writer, value) {
  writer.u8(value.tag);
  if (value.tag === TAG.NUMBER) writer.f64(value.number);
  else if (value.tag === TAG.STRING || value.tag === TAG.BYTES) writer.sized(value.bytes);
  else if (value.tag === TAG.FETCH) writer.u32(value.size);
}

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------

function answer(channel, id, record) {
  channel.answers.push({id, ...record});
  wake(channel);
}

async function dispatchCall(channel, id, name, args) {
  const handler = channel.handlers.get(name);
  if (!handler) {
    answer(channel, id, {ok: false, error: `no host answers ${name}`});
    return;
  }
  const controller = new AbortController();
  channel.inflight.set(id, controller);
  let results;
  try {
    results = await handler.call(args, {kind: name, signal: controller.signal});
  } catch (error) {
    answer(channel, id, {ok: false, error: String(error?.message || error)});
    return;
  } finally {
    channel.inflight.delete(id);
  }
  let values;
  try {
    values = checkedResults(name, results);
  } catch (error) {
    releaseResult(channel, {release: handler.release, values: Array.isArray(results) ? results : [results]});
    answer(channel, id, {ok: false, error: String(error?.message || error)});
    return;
  }
  if (channel.closed) {
    releaseResult(channel, {release: handler.release, values: results});
    return;
  }
  answer(channel, id, {ok: true, values, release: handler.release, results});
}

// A post or a send has no answer. What a post's results name is the page's to
// release, and a failure of either is reported, not raised.
function dispatchOneWay(channel, name, args, post) {
  const handler = channel.handlers.get(name);
  if (!handler) {
    channel.report(new Error(`no host answers ${name}`));
    return;
  }
  // Called now, as a call's handler is, so requests reach their handlers in the
  // order the application made them.
  let settling;
  try {
    settling = handler.call(args, {kind: name});
  } catch (error) {
    channel.report(error);
    return;
  }
  Promise.resolve(settling).then((results) => {
    if (post && results !== undefined) releaseResult(channel, {release: handler.release, values: results});
  }, (error) => channel.report(error));
}

function readRecords(channel, bytes) {
  const reader = new Reader(bytes);
  while (reader.remaining > 0) {
    const op = reader.u8();
    const id = reader.u32();
    if (op === OUT.CALL || op === OUT.POST || op === OUT.SEND) {
      const name = reader.text(reader.u16());
      // A malformed request stops the frame's records: everything after it
      // could be misread.
      const args = readArguments(channel, reader);
      let checked;
      try {
        checked = checkedKind(name);
      } catch (error) {
        if (op === OUT.CALL) answer(channel, id, {ok: false, error: String(error?.message || error)});
        else channel.report(error);
        continue;
      }
      if (op === OUT.CALL) dispatchCall(channel, id, checked, args);
      else dispatchOneWay(channel, checked, args, op === OUT.POST);
    } else if (op === OUT.CANCEL) {
      channel.inflight.get(id)?.abort(new Error("the caller stopped waiting"));
    } else if (op === OUT.ABANDON) {
      const result = reader.u32();
      const record = channel.results.get(result);
      if (record) {
        channel.results.delete(result);
        releaseResult(channel, record);
      }
    } else if (op === OUT.ABORT) {
      const transfer = reader.u32();
      const upload = channel.uploads.get(transfer);
      if (upload) {
        channel.uploads.delete(transfer);
        channel.reassembled -= upload.total;
      }
    } else if (op === OUT.ROUTES) {
      const routes = JSON.parse(reader.text(reader.u32()));
      channel.routes = routes && typeof routes === "object" && !Array.isArray(routes) ? routes : {};
    } else {
      throw new Error(`a host frame carried an unknown record ${op}`);
    }
  }
}

/**
 * Reads a frame's records and dispatches them. The frame lends one buffer: its
 * first `records` bytes are the application's records, and the page's answers
 * are written over it from the start once the frame has waited.
 */
export function beginHostFrame(effect, options) {
  const channel = channelOf(options);
  const spans = Array.isArray(effect.spans) ? effect.spans : effect.spans ? Object.values(effect.spans) : [];
  const inbox = spans[0];
  let failure;
  let lease;
  if (inbox) {
    try {
      lease = options.transfers.lease(inbox.lease, inbox.bytes, true);
      const records = effect.records | 0;
      if (records < 0 || records > lease.view.length) throw new Error("a host frame's records overrun its buffer");
      if (records > 0) readRecords(channel, lease.view.subarray(0, records));
    } catch (error) {
      failure = error;
    }
  }
  channel.frames.set(effect.id, {lease, inbox, failure});
}

/** Whether anything is ready for a frame's inbox. */
export function hostFrameReady(options) {
  const channel = options.hostChannel;
  return !!channel && (channel.answers.length > 0 || channel.inbound.length > 0 ||
    Object.keys(channel.dropped).length > 0);
}

/** Whether something the page is doing will produce an answer or a message. */
export function hostFrameWaitable(options) {
  const channel = options.hostChannel;
  return !!channel && !channel.closed && (channel.inflight.size > 0 || Object.keys(channel.routes).length > 0);
}

/** Calls `notify` once something is ready for a frame's inbox. */
export function onHostFrameReady(options, notify) {
  const channel = options.hostChannel;
  if (channel) channel.notify = notify;
}

// Applies each route's policy where the messages start, so what a route would
// drop never crosses: `latest` keeps a kind's newest message, `dropOldest` its
// newest `l`, and a kind nothing routes is dropped. Order across kinds is kept.
function applyPolicies(channel) {
  const routes = channel.routes;
  const totals = new Map();
  for (const message of channel.inbound) totals.set(message.kind, (totals.get(message.kind) || 0) + 1);
  const seen = new Map();
  const kept = [];
  for (const message of channel.inbound) {
    const route = routes[message.kind];
    const keep = !route ? 0 : route.p === "latest" ? 1 : Math.max(1, route.l | 0);
    const index = seen.get(message.kind) || 0;
    seen.set(message.kind, index + 1);
    if (index >= totals.get(message.kind) - keep) kept.push(message);
    else if (route) channel.dropped[message.kind] = (channel.dropped[message.kind] || 0) + 1;
  }
  channel.inbound = kept;
}

function encodeAnswer(channel, item) {
  const writer = new Writer(64);
  writer.u8(IN.ANSWER);
  writer.u32(item.id);
  if (!item.ok) {
    writer.u8(0);
    writer.sized(encoder.encode(item.error));
    return writer.result();
  }
  writer.u8(1);
  // Bytes too large to ride the inbox stay here, announced, until fetched.
  const fetched = item.values.filter((value) => value.tag === TAG.BYTES && value.bytes.byteLength > INLINE_BYTES);
  let result = 0;
  if (fetched.length > 0) {
    result = channel.nextResult++;
    channel.results.set(result, {
      views: item.values.map((value) => value.tag === TAG.BYTES ? value.bytes : null),
      remaining: fetched.reduce((total, value) => total + value.bytes.byteLength, 0),
      release: item.release,
      values: item.results,
    });
  }
  writer.u32(result);
  writer.u16(item.values.length);
  for (const value of item.values) {
    if (value.tag === TAG.BYTES && value.bytes.byteLength > INLINE_BYTES) {
      writeValue(writer, {tag: TAG.FETCH, size: value.bytes.byteLength});
    } else {
      writeValue(writer, value);
    }
  }
  return writer.result();
}

function encodeMessage(message) {
  const writer = new Writer(64);
  writer.u8(IN.MESSAGE);
  const kind = encoder.encode(message.kind);
  writer.u16(kind.length);
  writer.raw(kind);
  writer.u16(message.values.length);
  for (const value of message.values) writeValue(writer, value);
  return writer.result();
}

/** Fills a frame's inbox with what is ready and answers its request. */
export function finishHostFrame(effect, options) {
  const channel = channelOf(options);
  const frame = channel.frames.get(effect.id);
  channel.frames.delete(effect.id);
  if (!frame) throw new Error("a host frame was never begun");
  if (frame.failure) {
    if (frame.lease) options.transfers.release(frame.inbox.lease);
    throw frame.failure;
  }
  if (!frame.lease) return {written: 0};
  const view = frame.lease.view;
  let written = 0;
  let more = 0;
  try {
    const put = (bytes) => {
      if (written + bytes.length > view.length) {
        more ||= bytes.length;
        return false;
      }
      view.set(bytes, written);
      written += bytes.length;
      return true;
    };
    while (channel.answers.length > 0) {
      const item = channel.answers[0];
      const bytes = item.encoded ||= encodeAnswer(channel, item);
      if (!put(bytes)) break;
      channel.answers.shift();
    }
    if (more === 0) {
      applyPolicies(channel);
      for (const [kind, count] of Object.entries(channel.dropped)) {
        const writer = new Writer(32);
        writer.u8(IN.DROPPED);
        const name = encoder.encode(kind);
        writer.u16(name.length);
        writer.raw(name);
        writer.u32(count);
        if (!put(writer.result())) break;
        delete channel.dropped[kind];
      }
      while (more === 0 && channel.inbound.length > 0) {
        const message = channel.inbound[0];
        if (!put(message.encoded ||= encodeMessage(message))) break;
        channel.inbound.shift();
      }
    }
  } finally {
    options.transfers.release(frame.inbox.lease);
  }
  return more > 0 ? {written, more} : {written};
}

// ---------------------------------------------------------------------------
// Streams in
// ---------------------------------------------------------------------------

// Queues an inbound message, dropping the oldest past the bound, and wakes a
// frame waiting for something to deliver once this task's pushes are queued.
function pushMessage(channel, kind, values) {
  checkedKind(kind);
  if (values.length > MAX_VALUES) throw new Error(`host push ${kind} carries more than 255 values`);
  const checked = values.map((value, index) => inboundValue(kind, value, index + 1));
  if (channel.closed) return;
  channel.inbound.push({kind, values: checked});
  while (channel.inbound.length > MAX_INBOUND_MESSAGES) {
    const dropped = channel.inbound.shift();
    channel.dropped[dropped.kind] = (channel.dropped[dropped.kind] || 0) + 1;
  }
  if (channel.notify && !channel.wakeScheduled) {
    channel.wakeScheduled = true;
    queueMicrotask(() => {
      channel.wakeScheduled = false;
      wake(channel);
    });
  }
}

// ---------------------------------------------------------------------------
// Bulk bytes
// ---------------------------------------------------------------------------

function fetchResult(channel, effect, options) {
  const record = channel.results.get(effect.result);
  const span = Array.isArray(effect.spans) ? effect.spans[0] : undefined;
  try {
    if (!record) throw new Error("host result is unknown or was already released");
    const view = record.views[effect.index - 1];
    if (!view) throw new Error("host result has no such byte value");
    const lease = options.transfers.lease(span?.lease, undefined, true);
    const offset = effect.offset;
    if (!Number.isInteger(offset) || offset < 0 || offset + lease.view.length > view.length) {
      throw new Error("host result fetch range is invalid");
    }
    lease.view.set(view.subarray(offset, offset + lease.view.length));
    record.remaining -= lease.view.length;
    // The last byte delivered is the moment the application owns the result.
    if (record.remaining === 0) channel.results.delete(effect.result);
    return {bytes: lease.view.length};
  } finally {
    if (span) options.transfers.release(span.lease);
  }
}

function receiveUpload(channel, effect, options) {
  const span = Array.isArray(effect.spans) ? effect.spans[0] : undefined;
  try {
    const {transfer, offset, total} = effect;
    if (!Number.isInteger(transfer) || !Number.isInteger(total) || total < 0 || total > MAX_OUTBOUND_BYTES) {
      throw new Error("host upload is malformed");
    }
    let upload = channel.uploads.get(transfer);
    if (!upload) {
      if (offset !== 0) throw new Error("host upload began past its start");
      if (channel.reassembled + total > channel.reassemblyLimit) {
        throw new Error(`host upload of ${total} bytes exceeds the page's reassembly bound`);
      }
      upload = {bytes: new Uint8Array(total), total, received: 0};
      channel.uploads.set(transfer, upload);
      channel.reassembled += total;
    }
    const lease = options.transfers.lease(span?.lease, undefined, false);
    if (offset !== upload.received || offset + lease.view.length > total) {
      throw new Error("host upload chunk is out of order");
    }
    upload.bytes.set(lease.view, offset);
    upload.received += lease.view.length;
    return {received: upload.received};
  } finally {
    if (span) options.transfers.release(span.lease);
  }
}

/** Performs one bulk `host` effect: a fetch or an upload chunk. */
export async function performHostEffect(effect, options) {
  const channel = channelOf(options);
  switch (effect.op) {
    case "fetch":
      return fetchResult(channel, effect, options);
    case "upload":
      return receiveUpload(channel, effect, options);
    default:
      for (const span of Array.isArray(effect.spans) ? effect.spans : []) {
        try { options.transfers?.release(span?.lease); } catch {}
      }
      throw new Error(`unknown host operation ${effect.op}`);
  }
}

/** Whether a `host` effect is a frame, which `handleBrowserEffects` answers last. */
export function isHostFrame(effect) {
  return effect?.kind === "host" && effect.op === "x";
}

/** Fetches and uploads copy through a lease and settle at once. */
export function hostEffectBoundToFrame(effect) {
  return effect.op === "fetch" || effect.op === "upload";
}
