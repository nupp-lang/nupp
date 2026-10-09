// The page's entry to a packaged browser application, shipped as
// `nupp-browser-app.mjs`. Importing it starts nothing: the page calls `run`, once,
// with its own options, and only then is the application's Worker created.
const pending = new Map();
let worker = null;
let nextId = 1;
let launchedPromise = null;
// Host handlers that run on the page, by kind, and the calls in flight to them.
let pageHost = null;
const hostCalls = new Map();

function persistentStorage(event) {
  const requestId = event.data.requestId;
  Promise.resolve(globalThis.navigator?.storage?.persist?.()).then(
    (granted) => worker?.postMessage({type: "persistent-storage-response", requestId, granted: granted === true}),
    (error) => worker?.postMessage({
      type: "persistent-storage-response", requestId,
      error: String(error?.message || error),
    }),
  );
}

function hostHandler(kind) {
  const handler = pageHost?.handlers?.[kind];
  return typeof handler === "function" ? {call: handler} : handler;
}

function hostResults(answer) {
  return answer === undefined ? [] : Array.isArray(answer) ? answer : [answer];
}

function hostMessage(message) {
  if (message.type === "host-call") {
    const controller = new AbortController();
    hostCalls.set(message.requestId, controller);
    Promise.resolve()
      .then(() => hostHandler(message.kind).call(message.args, {kind: message.kind, signal: controller.signal}))
      .then(
        (answer) => worker?.postMessage({type: "host-answer", requestId: message.requestId, ok: true,
          results: hostResults(answer)}),
        (error) => worker?.postMessage({type: "host-answer", requestId: message.requestId, ok: false,
          error: String(error?.message || error)}),
      )
      .finally(() => hostCalls.delete(message.requestId));
  } else if (message.type === "host-cancel") {
    hostCalls.get(message.requestId)?.abort(new Error("the caller stopped waiting"));
  } else if (message.type === "host-release") {
    try { hostHandler(message.kind)?.release?.(message.results); } catch (error) { console.warn(error); }
  } else if (message.type === "host-end") {
    try { pageHost?.end?.(); } catch (error) { console.warn(error); }
  }
}

function openWorker() {
  worker = new Worker(new URL("./browser-worker.mjs", import.meta.url), {type: "module"});
  worker.addEventListener("message", (event) => {
    if (event.data?.type === "persistent-storage-request") {
      persistentStorage(event);
      return;
    }
    if (typeof event.data?.type === "string" && event.data.type.startsWith("host-")) {
      hostMessage(event.data);
      return;
    }
    const request = pending.get(event.data?.id);
    if (!request) return;
    pending.delete(event.data.id);
    if (event.data.ok) request.resolve(event.data.result);
    else request.reject(Object.assign(new Error(event.data.error?.message || "Nupp browser worker failed"), {
      stack: event.data.error?.stack,
    }));
  });
  worker.addEventListener("error", (event) => {
    for (const request of pending.values()) {
      request.reject(event.error || new Error(event.message));
    }
    pending.clear();
  });
}

function hostDescription(host) {
  if (host === undefined) return undefined;
  if (typeof host !== "object" || host === null) throw new Error("the host option must be an object");
  const handlers = host.handlers || {};
  for (const [kind, handler] of Object.entries(handlers)) {
    if (typeof handler !== "function" && typeof handler?.call !== "function") {
      throw new Error(`host handler ${kind} must be a function or an object with call`);
    }
  }
  pageHost = host;
  return {
    module: host.module === undefined ? undefined : new URL(host.module, globalThis.location?.href).href,
    kinds: Object.keys(handlers),
    end: typeof host.end === "function",
  };
}

/**
 * Starts the application and settles with its result. A page runs it once.
 *
 * `host` answers the application's `nupp.host` requests: `handlers` by kind on
 * the page, and `module`, a module URL loaded into the application's Worker
 * whose exported `handlers` answer there, nearer the application and without
 * a hop to the page. `end` runs once the application has finished.
 */
export function run(options = {}) {
  if (launchedPromise) return Promise.reject(new Error("this browser application already started"));
  let host;
  try {
    host = hostDescription(options.host);
  } catch (error) {
    return Promise.reject(error);
  }
  openWorker();
  const id = nextId++;
  // `limits` is the application's only deadline; the Worker enforces it.
  const result = new Promise((resolve, reject) => pending.set(id, {resolve, reject}));
  worker.postMessage({
    id,
    type: "run",
    manifest: new URL("./nupp-browser-app.json", import.meta.url).href,
    limits: options.limits,
    host,
    persistentStorageAvailable: typeof globalThis.navigator?.storage?.persist === "function",
  });
  launchedPromise = result;
  return result;
}

/** Asks a running application to stop; its `run` promise rejects with `reason`. */
export function cancel(reason = "the browser application was cancelled") {
  worker?.postMessage({type: "cancel", reason});
}

/** Terminates the application's Worker, rejecting a `run` still outstanding. */
export function close() {
  for (const request of pending.values()) {
    request.reject(new Error("the Nupp browser Worker was closed"));
  }
  pending.clear();
  worker?.terminate();
}
