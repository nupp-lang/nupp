import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { runNuppWasmApp } from "../../runtime/wasm/app-runtime.mjs";

const project = path.resolve(process.argv[2]);
const host = path.resolve(process.argv[3]);
const tier = process.argv[4] || "unknown";
const createHost = (await import(pathToFileURL(path.join(host, "nupp-app.mjs")).href)).default;
const manifest = JSON.parse(readFileSync(path.join(project, "dist/aot/units.json"), "utf8"));

if (manifest.schemaVersion !== 3 || manifest.target !== "wasm32-unknown-emscripten") {
  throw new Error("unexpected Wasm AOT artifact manifest");
}
if (!manifest.units.every((unit) => /^[a-z0-9/_.-]+\.[0-9a-f]{16}\.wasm$/.test(unit.wasm))) {
  throw new Error("Wasm AOT side modules are not content-addressed");
}

await runNuppWasmApp({
  createHost: async (options) => {
    const runtime = await createHost(options);
    // Unoptimized side modules retain these libc calls instead of Wasm abs
    // instructions. Check the actual linked host, including signed zero.
    for (const name of ["_fabs", "_fabsf"]) {
      assert.equal(typeof runtime[name], "function", `missing side-module libm export ${name}`);
      assert.equal(runtime[name](-3.5), 3.5);
      assert.ok(Object.is(runtime[name](-0), 0));
      assert.equal(runtime[name](-Infinity), Infinity);
      assert.ok(Number.isNaN(runtime[name](NaN)));
    }
    return runtime;
  },
  locateFile: (name) => path.isAbsolute(name) ? name : path.join(host, name),
  app: readFileSync(path.join(project, "dist/app.lua")),
  sideModules: manifest.units.map((unit) => ({
    url: path.join(project, "dist/aot", unit.wasm),
    registrar: unit.registrar,
  })),
  wasmBinary: readFileSync(path.join(host, "nupp-app.wasm")),
});

console.log("Nupp Lua 5.1 Wasm struct AOT passed (" + tier + ")");
