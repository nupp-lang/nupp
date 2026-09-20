// Rebind only generated Lua C wrappers to their existing scalar-C twins.
// Keep the original project and SIMD side modules unchanged for comparison.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import path from 'node:path';

const project = path.resolve(process.argv[2]);
const output = path.resolve(process.argv[3]);
const compiler = process.env.NUPP_WASM_CC || process.env.EMCC || 'emcc';
if (existsSync(output)) throw new Error(`Refusing to overwrite scalar-C evidence: ${output}`);
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const manifest = JSON.parse(readFileSync(path.join(project, 'dist/aot/units.json'), 'utf8'));
if (manifest.schemaVersion !== 3 || manifest.target !== 'wasm32-unknown-emscripten' ||
    !manifest.units.length || manifest.units.some((unit) => unit.tier !== 'simd128')) {
  throw new Error('Scalar-C adapter requires generated SIMD128 side modules');
}
mkdirSync(path.join(output, 'dist/aot'), { recursive: true });
writeFileSync(path.join(output, 'corpus.json'), readFileSync(path.join(project, 'corpus.json')));
if (existsSync(path.join(project, 'regions.json'))) {
  writeFileSync(path.join(output, 'regions.json'), readFileSync(path.join(project, 'regions.json')));
}
writeFileSync(path.join(output, 'dist/app.lua'), readFileSync(path.join(project, 'dist/app.lua')));
const referenceText = readFileSync(path.join(project, 'result.json'), 'utf8');
const reference = JSON.parse(referenceText);
if (!reference.ok || !reference.nativeCalls || !reference.symbols || reference.scalarSelection ||
    (reference.executionPath && reference.executionPath !== 'simd')) throw new Error('Run the SIMD corpus before preparing its scalar-C twin');
const selection = { executionPath: 'scalar-c', originalProject: project,
  referenceExecutionSha256: sha256(referenceText), referenceCases: reference.cases,
  referenceCalls: reference.nativeCalls, referenceProbes: reference.probes, units: [] };
const units = [];
for (const unit of manifest.units) {
  const relative = unit.source.replace(/\.c$/, '.side.c');
  const original = readFileSync(path.join(project, 'build/app/aot', relative), 'utf8');
  const boundary = original.indexOf('/* The stock Lua 5.1 host binding');
  if (boundary < 0) throw new Error(`Missing generated Lua C binding boundary: ${relative}`);
  const kernels = original.slice(0, boundary);
  const symbols = {};
  const binding = original.slice(boundary).replace(/\b(ks_[A-Za-z0-9_]+)__simd128(?=\s*\()/g, (_, symbol) => {
    const scalar = `${symbol}_forced_scalar__simd128`;
    const declaration = new RegExp(`KS_SCALAR_ORACLE\\s+__attribute__\\(\\(noinline\\)\\)\\s+KS_API[^;{}]+\\b${scalar}\\(`);
    if (!declaration.test(kernels)) throw new Error(`Missing unoptimized emitted scalar-C twin: ${scalar}`);
    if (symbols[symbol]) throw new Error(`Repeated Lua wrapper call for ${symbol}`);
    symbols[symbol] = scalar;
    return scalar;
  });
  if (!Object.keys(symbols).length) throw new Error(`No scalar-C wrapper calls selected: ${relative}`);
  const source = kernels + binding;
  const sourcePath = path.join(output, 'build/app/aot', relative);
  mkdirSync(path.dirname(sourcePath), { recursive: true });
  writeFileSync(sourcePath, source);
  const staged = sourcePath.replace(/\.c$/, '.wasm');
  const args = [sourcePath, '-std=c11', '-O3', '-ffp-contract=off', '-fno-fast-math',
    '-Wall', '-Wextra', '-Werror', '-Wno-parentheses-equality', '-sSIDE_MODULE=2',
    '-sFILESYSTEM=0', ...(unit.cflags || []), '-o', staged];
  const result = spawnSync(compiler, args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  writeFileSync(sourcePath + '.compile.log', `${compiler} ${args.map((arg) => JSON.stringify(arg)).join(' ')}\n${result.stdout || ''}${result.stderr || ''}`);
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`Scalar-C side module failed: ${sourcePath}.compile.log`);
  const wasm = readFileSync(staged);
  const digest = sha256(wasm);
  const wasmRelative = unit.source.replace(/\.c$/, `.${digest.slice(0, 16)}.wasm`);
  const wasmPath = path.join(output, 'dist/aot', wasmRelative);
  mkdirSync(path.dirname(wasmPath), { recursive: true });
  writeFileSync(wasmPath, wasm);
  units.push({ ...unit, wasm: wasmRelative });
  selection.units.push({ unit: unit.unit, symbols, source: `build/app/aot/${relative}`,
    originalSourceSha256: sha256(original), sourceSha256: sha256(source),
    originalWasmSha256: sha256(readFileSync(path.join(project, 'dist/aot', unit.wasm))),
    wasm: wasmRelative, wasmSha256: digest });
}
for (const [probe, symbol] of Object.entries(reference.symbols)) {
  const selected = selection.units.filter((unit) => unit.symbols[symbol]);
  if (selected.length !== 1) throw new Error(`Expected exactly one scalar-C wrapper replacement for ${probe}`);
}
writeFileSync(path.join(output, 'dist/aot/units.json'), JSON.stringify({ ...manifest, units }, null, 2) + '\n');
writeFileSync(path.join(output, 'scalar-selection.json'), JSON.stringify(selection, null, 2) + '\n');
console.log(`Prepared ${units.length} scalar-C Wasm units in ${output}`);
