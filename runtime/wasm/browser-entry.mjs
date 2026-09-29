// The page's entry to a packaged browser application, shipped as
// `nupp-browser-app.mjs`. Importing it starts nothing: the page calls `run`, once,
// with its own options, and only then is the application's Worker created.
const pending = new Map();
let worker = null;
let nextId = 1;
let launchedPromise = null;

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

function openWorker() {
  worker = new Worker(new URL("./browser-worker.mjs", import.meta.url), {type: "module"});
  worker.addEventListener("message", (event) => {
    if (event.data?.type === "persistent-storage-request") {
      persistentStorage(event);
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

/** Starts the application and settles with its result. A page runs it once. */
export function run(options = {}) {
  if (launchedPromise) return Promise.reject(new Error("this browser application already started"));
  openWorker();
  const id = nextId++;
  // `limits` is the application's only deadline; the Worker enforces it.
  const result = new Promise((resolve, reject) => pending.set(id, {resolve, reject}));
  worker.postMessage({
    id,
    type: "run",
    manifest: new URL("./nupp-browser-app.json", import.meta.url).href,
    limits: options.limits,
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
