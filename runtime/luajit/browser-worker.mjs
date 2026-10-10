import { runPackagedNuppLuaJITApp } from "./app-runtime.mjs";

let active;
let nextPersistenceRequest = 1;
const persistenceRequests = new Map();
let nextHostCall = 1;
const hostCalls = new Map();
// The running application's push, once its channel has opened; pushes that
// arrive before then wait for it.
let hostPush = null;
const earlyPushes = [];

function transferables(values) {
  return values.filter((value) => ArrayBuffer.isView(value)).map((value) => value.buffer);
}

// A kind the page answers: the Worker forwards each call, its cancellation and
// any release of its results, and the page's answer comes back by request id.
function pageHandler(kind) {
  return {
    call(args, {signal} = {}) {
      const requestId = nextHostCall++;
      return new Promise((resolve, reject) => {
        hostCalls.set(requestId, {resolve, reject});
        // A post or a send has no caller to stop waiting, and so no signal.
        signal?.addEventListener("abort", () => self.postMessage({type: "host-cancel", requestId}), {once: true});
        self.postMessage({type: "host-call", requestId, kind, args}, transferables(args));
      });
    },
    release(results) {
      self.postMessage({type: "host-release", kind, results});
    },
  };
}

async function hostOption(description) {
  if (!description) return undefined;
  const handlers = {};
  let moduleEnd;
  let moduleStart;
  if (description.module) {
    const loaded = await import(description.module);
    Object.assign(handlers, loaded.handlers || {});
    moduleEnd = loaded.end;
    moduleStart = loaded.start;
  }
  for (const kind of description.kinds || []) {
    if (Object.hasOwn(handlers, kind)) throw new Error(`host kind ${kind} is answered by both the page and its module`);
    handlers[kind] = pageHandler(kind);
  }
  return {
    handlers,
    start(api) {
      hostPush = api.push;
      for (const [kind, values] of earlyPushes.splice(0)) hostPush(kind, ...values);
      moduleStart?.(api);
    },
    end() {
      hostPush = null;
      try { moduleEnd?.(); } finally { if (description.end) self.postMessage({type: "host-end"}); }
    },
  };
}

function requestPersistentStorage() {
  const requestId = nextPersistenceRequest++;
  self.postMessage({type: "persistent-storage-request", requestId});
  return new Promise((resolve, reject) => persistenceRequests.set(requestId, {resolve, reject}));
}

self.addEventListener("message", async (event) => {
  const message = event.data;
  if (message?.type === "persistent-storage-response") {
    const request = persistenceRequests.get(message.requestId);
    if (!request) return;
    persistenceRequests.delete(message.requestId);
    if (message.error) request.reject(new Error(message.error));
    else request.resolve(message.granted === true);
    return;
  }
  if (message?.type === "host-push") {
    try {
      if (hostPush) hostPush(message.kind, ...(message.values || []));
      else if (earlyPushes.length < 4096) earlyPushes.push([message.kind, message.values || []]);
    } catch (error) {
      console.warn(error);
    }
    return;
  }
  if (message?.type === "host-answer") {
    const call = hostCalls.get(message.requestId);
    if (!call) return;
    hostCalls.delete(message.requestId);
    if (message.ok) call.resolve(message.results);
    else call.reject(new Error(message.error));
    return;
  }
  if (message?.type === "cancel") {
    active?.abort(new Error(message.reason || "the browser application was cancelled"));
    return;
  }
  if (message?.type !== "run" || !Number.isInteger(message.id)) return;
  if (active) {
    self.postMessage({
      id: message.id,
      ok: false,
      error: {message: "a Nupp browser application is already running"},
    });
    return;
  }

  const controller = new AbortController();
  active = controller;
  try {
    const result = await runPackagedNuppLuaJITApp(message.manifest, {
      host: await hostOption(message.host),
      signal: controller.signal,
      limits: message.limits,
      storageName: message.storageName,
      requestPersistentStorage: message.persistentStorageAvailable ? requestPersistentStorage : undefined,
    });
    self.postMessage({id: message.id, ok: true, result});
  } catch (error) {
    self.postMessage({
      id: message.id,
      ok: false,
      error: {message: String(error?.message || error), stack: error?.stack},
    });
  } finally {
    active = undefined;
  }
});
