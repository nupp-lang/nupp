import { runNuppWasmApp } from "../../../runtime/wasm/app-runtime.mjs";

const encoder = new TextEncoder();

async function sha256(bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function verifiedRuntime() {
  const response = await fetch(new URL(`./${__NUPP_APP_RUNTIME_ASSET__}`, import.meta.url));
  if (!response.ok) throw new Error(`fetching the checked application runtime: ${response.status}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  const actual = await sha256(bytes);
  if (actual !== __NUPP_APP_RUNTIME_SHA256__) {
    throw new Error(`application runtime SHA-256 mismatch: expected ${__NUPP_APP_RUNTIME_SHA256__}, found ${actual}`);
  }
  return bytes;
}

self.addEventListener("message", async (event) => {
  if (event.data?.type !== "run" || typeof event.data.code !== "string") return;
  const controller = new AbortController();
  try {
    const program = encoder.encode(event.data.code);
    if (program.length > 8 * 1024 * 1024) {
      throw new Error("the generated application exceeded 8 MiB");
    }
    const programDigest = await sha256(program);
    const [createHost, initialize, wasmResponse] = await Promise.all([
      import(new URL("./nupp-runner.mjs", import.meta.url)).then((module) => module.default),
      verifiedRuntime(),
      fetch(new URL("./nupp-runner.wasm", import.meta.url)),
    ]);
    if (!wasmResponse.ok) throw new Error(`fetching the application VM: ${wasmResponse.status}`);
    const result = await runNuppWasmApp({
      createHost,
      locateFile: (name) => new URL(name, import.meta.url).href,
      app: program,
      initialize,
      managed: true,
      sideModules: [],
      wasmBinary: new Uint8Array(await wasmResponse.arrayBuffer()),
      signal: controller.signal,
      limits: {
        maxEffects: 128,
        maxEffectBytes: 2 * 1024 * 1024,
        maxResponseBytes: 4 * 1024 * 1024,
        maxStorageValueBytes: 512 * 1024,
        deadlineMs: 5000,
      },
      storageName: `nupp-playground-${programDigest.slice(0, 24)}`,
    });
    self.postMessage({ok: true, result});
  } catch (error) {
    self.postMessage({ok: false, error: String(error?.message || error)});
  }
});
