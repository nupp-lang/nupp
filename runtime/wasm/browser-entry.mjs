const worker = new Worker(new URL("./browser-worker.mjs", import.meta.url), {type: "module"});
const pending = new Map();
let nextId = 1;
let launched = false;

worker.addEventListener("message", (event) => {
  const request = pending.get(event.data?.id);
  if (!request) return;
  pending.delete(event.data.id);
  clearTimeout(request.timeout);
  if (event.data.ok) request.resolve(event.data.result);
  else request.reject(Object.assign(new Error(event.data.error?.message || "Nupp browser worker failed"), {
    stack: event.data.error?.stack,
  }));
});

worker.addEventListener("error", (event) => {
  for (const request of pending.values()) {
    clearTimeout(request.timeout);
    request.reject(event.error || new Error(event.message));
  }
  pending.clear();
});

export function run(options = {}) {
  if (launched) return Promise.reject(new Error("this browser application already started"));
  launched = true;
  const id = nextId++;
  const deadlineMs = options.deadlineMs || 30_000;
  const result = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      pending.delete(id);
      worker.terminate();
      reject(new Error(`the Nupp browser application exceeded its ${deadlineMs} ms hard deadline`));
    }, deadlineMs);
    pending.set(id, {resolve, reject, timeout});
  });
  worker.postMessage({
    id,
    type: "run",
    manifest: new URL("./nupp-browser-app.json", import.meta.url).href,
    limits: options.limits,
    storageName: options.storageName,
  });
  return result;
}

export function cancel(reason = "the browser application was cancelled") {
  worker.postMessage({type: "cancel", reason});
}

export function close() {
  for (const request of pending.values()) {
    clearTimeout(request.timeout);
    request.reject(new Error("the Nupp browser Worker was closed"));
  }
  pending.clear();
  worker.terminate();
}

export const ready = run();

export default ready;
