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

const MAX_STRING_BYTES = 64 * 1024;
const MAX_OUTBOUND_BYTES = 64 * 1024 * 1024;
const MAX_INBOUND_BYTES = 8 * 1024 * 1024;
const MAX_VALUES = 255;
const DEFAULT_REASSEMBLY_BYTES = 128 * 1024 * 1024;
const KIND = /^[\w-]+\.[\w.-]*[\w-]$/;
const encoder = new TextEncoder();

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
  return {
    handlers: normalizedHandlers(host.handlers),
    end: host.end,
    report: typeof host.onError === "function" ? host.onError : (error) => console.warn(error),
    reassemblyLimit,
    reassembled: 0,
    uploads: new Map(),
    results: new Map(),
    inflight: new Map(),
    nextResult: 1,
    closed: false,
  };
}

function channelOf(options) {
  return options.hostChannel ||= createHostChannel(options.host);
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
  for (const record of channel.results.values()) releaseResult(channel, record);
  channel.results.clear();
  channel.uploads.clear();
  channel.reassembled = 0;
  try {
    channel.end?.();
  } catch (error) {
    channel.report(error);
  }
}

// Copies a request's leased bytes and releases every lease it names before
// anything can fail, so the frame that carried it can be answered at once.
function takeSpans(effect, options) {
  const spans = Array.isArray(effect.spans) ? effect.spans : effect.spans ? Object.values(effect.spans) : [];
  const copies = [];
  let failure;
  for (const span of spans) {
    try {
      const lease = options.transfers.lease(span?.lease, span?.bytes, false);
      copies.push(lease.view.slice());
    } catch (error) {
      failure ||= error;
    } finally {
      try { options.transfers.release(span?.lease); } catch {}
    }
  }
  if (failure) throw failure;
  return copies;
}

function encodedEntries(effect) {
  const encoded = effect.v;
  if (encoded === undefined || encoded === null) return () => undefined;
  if (Array.isArray(encoded)) return (position) => encoded[position - 1];
  if (typeof encoded === "object") return (position) => encoded[String(position)];
  throw new Error("host request values are malformed");
}

function decodeArguments(channel, effect, copies) {
  const count = effect.n;
  if (!Number.isInteger(count) || count < 0 || count > MAX_VALUES) {
    throw new Error("host request has no valid value count");
  }
  const entry = encodedEntries(effect);
  const args = new Array(count);
  for (let position = 1; position <= count; position++) {
    const value = entry(position);
    if (value === undefined || value === null) {
      args[position - 1] = null;
    } else if (typeof value === "object") {
      if (Number.isInteger(value.bytes)) {
        const bytes = copies[value.bytes - 1];
        if (!bytes) throw new Error(`host request value ${position} names a missing byte span`);
        args[position - 1] = bytes;
      } else if (Number.isInteger(value.transfer)) {
        const upload = channel.uploads.get(value.transfer);
        if (!upload || upload.received !== upload.total) {
          throw new Error(`host request value ${position} names an incomplete upload`);
        }
        channel.uploads.delete(value.transfer);
        channel.reassembled -= upload.total;
        args[position - 1] = upload.bytes;
      } else {
        throw new Error(`host request value ${position} is malformed`);
      }
    } else {
      args[position - 1] = value;
    }
  }
  return args;
}

function asBytes(value) {
  if (value instanceof Uint8Array) return value;
  if (ArrayBuffer.isView(value)) return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  if (value instanceof ArrayBuffer) return new Uint8Array(value);
  return null;
}

// Validates a handler's answer against the value model and splits its byte values
// out to be fetched.
function encodeResults(name, answer) {
  const results = answer === undefined ? [] : Array.isArray(answer) ? answer : [answer];
  if (results.length > MAX_VALUES) throw new Error(`host handler ${name} answered more than 255 values`);
  const encoded = {};
  const bytes = [];
  results.forEach((value, index) => {
    const position = index + 1;
    if (value === null || value === undefined) return;
    const view = asBytes(value);
    if (view) {
      if (view.byteLength > MAX_INBOUND_BYTES) {
        throw new Error(`host handler ${name} result ${position} is more than 8 MiB of bytes`);
      }
      bytes.push({index: position, size: view.byteLength, view});
      return;
    }
    if (typeof value === "boolean") {
      encoded[position] = value;
    } else if (typeof value === "number") {
      if (!Number.isFinite(value)) throw new Error(`host handler ${name} result ${position} is not a finite number`);
      encoded[position] = value;
    } else if (typeof value === "string") {
      if (value.isWellFormed?.() === false) throw new Error(`host handler ${name} result ${position} is not valid text`);
      if (encoder.encode(value).length > MAX_STRING_BYTES) {
        throw new Error(`host handler ${name} result ${position} is a string longer than 64 KiB; answer bytes`);
      }
      encoded[position] = value;
    } else {
      throw new Error(`host handler ${name} result ${position} is a ${typeof value}, which cannot cross`);
    }
  });
  return {count: results.length, encoded, bytes, results};
}

async function callHandler(channel, effect, options) {
  const name = checkedKind(effect.name);
  let copies;
  try {
    copies = takeSpans(effect, options);
  } catch (error) {
    throw new Error(`host request ${name} carried an invalid byte span: ${error?.message || error}`);
  }
  const args = decodeArguments(channel, effect, copies);
  const handler = channel.handlers.get(name);
  if (!handler) throw new Error(`no host answers ${name}`);
  const controller = new AbortController();
  channel.inflight.set(effect.id, controller);
  let answer;
  try {
    answer = await handler.call(args, {kind: name, signal: controller.signal});
  } finally {
    channel.inflight.delete(effect.id);
  }
  let encoded;
  try {
    encoded = encodeResults(name, answer);
  } catch (error) {
    releaseResult(channel, {release: handler.release, values: Array.isArray(answer) ? answer : [answer]});
    throw error;
  }
  if (effect.op === "post" || channel.closed) {
    // Nobody takes a post's results, so whatever they name is the page's to release.
    if (encoded.count > 0) releaseResult(channel, {release: handler.release, values: encoded.results});
    return {n: 0, v: {}};
  }
  if (encoded.bytes.length === 0) return {n: encoded.count, v: encoded.encoded};
  const remaining = encoded.bytes.reduce((total, entry) => total + entry.size, 0);
  const result = channel.nextResult++;
  const announced = {
    n: encoded.count,
    v: encoded.encoded,
    result,
    bytes: encoded.bytes.map(({index, size}) => ({index, size})),
  };
  // Empty byte values need no fetch, so the application owns them at once.
  if (remaining === 0) return announced;
  channel.results.set(result, {
    name,
    values: encoded.results,
    views: encoded.bytes.map((entry) => entry.view),
    remaining,
    release: handler.release,
  });
  return announced;
}

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

/** Performs one `host` effect: a call, a post, or the channel's own bookkeeping. */
export async function performHostEffect(effect, options) {
  const channel = channelOf(options);
  switch (effect.op) {
    case "call":
    case "post":
      return callHandler(channel, effect, options);
    case "fetch":
      return fetchResult(channel, effect, options);
    case "upload":
      return receiveUpload(channel, effect, options);
    case "abandon": {
      const record = channel.results.get(effect.result);
      if (record) {
        channel.results.delete(effect.result);
        releaseResult(channel, record);
      }
      return {};
    }
    case "abort": {
      const upload = channel.uploads.get(effect.transfer);
      if (upload) {
        channel.uploads.delete(effect.transfer);
        channel.reassembled -= upload.total;
      }
      return {};
    }
    case "cancel":
      channel.inflight.get(effect.target)?.abort(new Error("the caller stopped waiting"));
      return {};
    default:
      for (const span of Array.isArray(effect.spans) ? effect.spans : []) {
        try { options.transfers?.release(span?.lease); } catch {}
      }
      throw new Error(`unknown host operation ${effect.op}`);
  }
}

/**
 * Whether a host effect must be answered in the frame that carried it. A call or
 * post releases its leases when dispatched and may then take as long as its
 * handler does; a fetch or upload copies through a lease and settles at once.
 */
export function hostEffectBoundToFrame(effect) {
  return effect.op === "fetch" || effect.op === "upload";
}
