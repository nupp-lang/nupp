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
    // Every portable admitted map must link through real host math, including
    // scalar-C twins where Wasm instructions do not replace libm calls.
    for (const name of ["sqrt", "sqrtf", "floor", "floorf", "ceil", "ceilf", "sin", "cos", "tan",
      "asin", "acos", "atan", "exp", "log", "pow", "fmod", "fmodf"]) {
      assert.equal(typeof runtime["_" + name], "function", `missing math map export ${name}`);
    }
    for (const name of ["sin", "tan", "asin", "atan", "sqrt", "sqrtf", "floor", "floorf", "ceil", "ceilf"]) {
      assert.ok(Object.is(runtime["_" + name](-0), -0), `${name} preserves negative zero`);
    }
    assert.equal(runtime._cos(0), 1);
    assert.equal(runtime._acos(1), 0);
    assert.equal(runtime._exp(0), 1);
    assert.equal(runtime._log(1), 0);
    assert.equal(runtime._pow(2, 3), 8);
    assert.ok(Object.is(runtime._fmod(-0, 3), -0));
    assert.ok(Object.is(runtime._fmodf(-0, 3), -0));
    assert.ok(Number.isNaN(runtime._sqrt(-1)));
    assert.equal(runtime._exp(Infinity), Infinity);
    // Fused decimal parsing uses libc conversion/byte routines and the
    // compiler runtime's wide multiplication helper through the same linker.
    for (const name of ["_strtod", "_memcmp", "_memchr", "___multi3"]) {
      assert.equal(typeof runtime[name], "function", `missing side-module runtime export ${name}`);
    }
    const bytes = runtime._malloc(64);
    try {
      runtime.HEAPU8.set(Buffer.from("-0\0-12.5x\0"), bytes);
      assert.ok(Object.is(runtime._strtod(bytes, 0), -0));
      assert.equal(runtime._strtod(bytes + 3, 0), -12.5);
      assert.equal(runtime._memchr(bytes, 120, 10), bytes + 8);
      assert.equal(runtime._memchr(bytes, 122, 10), 0);
      assert.equal(runtime._memcmp(bytes, bytes, 10), 0);
      assert.ok(runtime._memcmp(bytes + 1, bytes + 4, 1) < 0);
      // (2^64 + 3) * (2^64 + 5), modulo the helper's 128-bit result.
      runtime.___multi3(bytes + 16, 3n, 1n, 5n, 1n);
      const result = new DataView(runtime.HEAPU8.buffer);
      assert.equal(result.getBigUint64(bytes + 16, true), 15n);
      assert.equal(result.getBigUint64(bytes + 24, true), 8n);
    } finally { runtime._free(bytes); }
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
