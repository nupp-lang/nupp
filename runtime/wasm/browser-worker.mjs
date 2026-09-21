import { runPackagedNuppWasmApp } from "./app-runtime.mjs";

let active;
let nextPersistenceRequest = 1;
const persistenceRequests = new Map();

function requestPersistentStorage() {
  const requestId = nextPersistenceRequest++;
  return new Promise((resolve, reject) => {
    persistenceRequests.set(requestId, {resolve, reject});
    self.postMessage({type: "persistent-storage-request", requestId});
  });
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
    const result = await runPackagedNuppWasmApp(message.manifest, {
      signal: controller.signal,
      limits: message.limits,
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
