// Runs the exact stock-Lua compiler bundle tested during the build inside a
// filesystem-free Lua 5.1 VM compiled to Wasm.
import { createCompilerHost } from "./wasm-runtime.js";

let host = null;
let ready = false;

async function boot() {
  const moduleUrl = new URL("./nupp-playground.mjs", import.meta.url).href;
  const wasmUrl = new URL("./nupp-playground.wasm", import.meta.url).href;
  const compilerUrl = new URL(`./${__NUPP_COMPILER_ASSET__}`, import.meta.url).href;

  postMessage({ type: "status", message: "starting the Lua 5.1 VM…" });
  host = await createCompilerHost({
    moduleUrl,
    wasmUrl,
    compilerUrl,
    expectedDigest: __NUPP_COMPILER_SHA256__,
  });
  ready = true;
  postMessage({ type: "ready", timings: host.timings });
}

self.onmessage = (event) => {
  const { id, kind, source, filename, offset, options } = event.data;
  if (!ready) {
    postMessage({ id, ok: false, error: "the compiler is still loading" });
    return;
  }
  try {
    if (kind !== "check" && kind !== "compile" && kind !== "hover") {
      postMessage({ id, ok: false, error: `unknown request kind "${kind}"` });
      return;
    }
    if (typeof source === "string" && new TextEncoder().encode(source).length > 1024 * 1024) {
      postMessage({id, ok: false, error: "playground source exceeds 1048576 UTF-8 bytes"});
      return;
    }
    const response = host.request({
      kind,
      source,
      filename: filename || "playground.nupp",
      offset,
      options,
    });
    postMessage({ id, ok: true, ...response });
  } catch (error) {
    postMessage({
      id,
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
};

function describeError(error) {
  if (!(error instanceof Error)) return String(error);
  return error.stack && error.stack.includes(error.message)
    ? error.stack
    : `${error.message}\n${error.stack || ""}`;
}

boot().catch((error) => {
  postMessage({ type: "boot-error", message: describeError(error) });
});
