// Execute the same generated semantic corpus through the existing Wasm host.
// Wrap registrar-installed entries before any authored module loads, proving
// that every named probe calls the native side module rather than Lua fallback.
import { readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { runNuppWasmApp } from "../../runtime/wasm/app-runtime.mjs";

const project = path.resolve(process.argv[2]);
const host = path.resolve(process.argv[3]);
const corpus = JSON.parse(readFileSync(path.join(project, "corpus.json"), "utf8"));
const manifest = JSON.parse(readFileSync(path.join(project, "dist/aot/units.json"), "utf8"));
if (manifest.schemaVersion !== 3 || manifest.target !== "wasm32-unknown-emscripten" ||
    !manifest.units.length || manifest.units.some((unit) => unit.tier !== "simd128")) {
  throw new Error("SIMD conformance requires actual simd128 side modules");
}
const source = readFileSync(path.join(project, "dist/app.lua"), "utf8");
// Read the emitted binding's actual symbol and unit, including module-private
// qualification and the compiler's camel-case conversion. Do not recreate it.
const bindings = [];
const bindingPattern = /\b(__nuppWasm_[A-Za-z0-9_]+)Native\s*=\s*assert\s*\(\s*\1Unit\s*\[\s*"([^"]+)"\s*\]\s*,\s*"Wasm AOT kernel ([^"]+) is not registered"\s*\)/g;
for (const match of source.matchAll(bindingPattern)) {
  const unitPattern = new RegExp(`\\b${match[1]}Unit\\s*=\\s*assert\\s*\\(\\s*${match[1]}Registry\\s*\\[\\s*"([^"]+)"`);
  const unit = source.match(unitPattern)?.[1];
  if (!unit) throw new Error(`Missing emitted unit binding for ${match[3]}`);
  bindings.push({ symbol: match[2], name: match[3], unit });
}
const probes = [];
for (const [module, names] of Object.entries(corpus.probes)) {
  const suffixes = [`/${module}.simd128.c`, `/${module}.g.simd128.c`];
  const units = manifest.units.filter((unit) => suffixes.some((suffix) => unit.source.endsWith(suffix)));
  if (units.length !== 1 || !units[0].unit) throw new Error(`missing unique Wasm unit for ${module}`);
  for (const name of names) {
    if (!/^[A-Za-z0-9_]+$/.test(name)) throw new Error(`probe must have an explicit C-safe name: ${name}`);
    const selected = bindings.filter((binding) => binding.unit === units[0].unit && binding.name === name);
    if (selected.length !== 1) throw new Error(`Missing unique emitted binding for ${module}.${name}`);
    probes.push({ key: `${module}.${name}`, ...selected[0] });
  }
}
if (!probes.length) throw new Error("empty Wasm native probe inventory");
const declarations = probes.map(({ key, unit, symbol }) =>
  `observe(${JSON.stringify(unit)}, ${JSON.stringify(symbol)}, ${JSON.stringify(key)})`).join("\n");
const prefix = `
local registry = assert(rawget(_G, "__nuppWasmAot"), "Wasm registry missing")
local calls, symbols = {}, {}
local function pack(...) return {n=select("#", ...), ...} end
local function observe(unit, symbol, key)
  local entries = assert(registry[unit], "Wasm unit missing: " .. unit)
  local native = assert(entries[symbol], "native probe missing: " .. key)
  symbols[key] = symbol
  assert(type(native) == "function", "registered native probe is not callable")
  calls[key] = 0
  entries[symbol] = function(...)
    local result = pack(native(...))
    calls[key] = calls[key] + 1
    return unpack(result, 1, result.n)
  end
end
${declarations}
local entry = (function()
`;
const suffix = `
end)()
local checked = assert(entry.run, "corpus entry lacks run")()
assert(type(checked) == "number" and checked > 0, "Wasm corpus checked no cases")
local total, probes = 0, 0
for key, count in pairs(calls) do
  assert(count > 0, "probe never called its Wasm native entry: " .. key)
  total, probes = total + count, probes + 1
end
return string.format('{"cases":%.0f,"nativeCalls":%.0f,"probes":%.0f}', checked, total, probes)
`;
const createHost = (await import(pathToFileURL(path.join(host, "nupp-app.mjs")).href)).default;
const app = Buffer.from(prefix + source + suffix);
const result = await runNuppWasmApp({
  createHost,
  locateFile: (name) => path.isAbsolute(name) ? name : path.join(host, name),
  app,
  sideModules: manifest.units.map((unit) => ({
    url: path.join(project, "dist/aot", unit.wasm), registrar: unit.registrar,
  })),
  wasmBinary: readFileSync(path.join(host, "nupp-app.wasm")),
});
if (result?.probes !== probes.length || !(result.nativeCalls > 0) || !(result.cases > 0)) {
  throw new Error(`missing completed Wasm execution proof: ${JSON.stringify(result)}`);
}
const artifacts = manifest.units.map((unit) => ({
  ...unit,
  sha256: createHash("sha256").update(readFileSync(path.join(project, "dist/aot", unit.wasm))).digest("hex"),
}));
const hostArtifacts = ["nupp-app.mjs", "nupp-app.wasm"].map((name) => ({
  name, sha256: createHash("sha256").update(readFileSync(path.join(host, name))).digest("hex"),
}));
const report = { ok: true, hostArtifacts,
  appSha256: createHash("sha256").update(source).digest("hex"), tier: "simd128", runtime: "existing Lua 5.1 Wasm host / Node",
  ...result, symbols: Object.fromEntries(probes.map((probe) => [probe.key, probe.symbol])),
  coverage: corpus.coverage, artifacts };
writeFileSync(path.join(project, "result.json"), JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify(report));
