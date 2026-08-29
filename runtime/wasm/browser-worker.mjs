import { runPackagedNuppWasmApp } from "./app-runtime.mjs";

let active;

self.addEventListener("message", async (event) => {
  const message = event.data;
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
      storageName: message.storageName,
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
