import test from 'node:test';
import assert from 'node:assert/strict';
import { algorithms, summarizeAlgorithms } from './wasm-algorithm-evidence.mjs';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { verifyOriginalSources } from './wasm-algorithm-oracles.mjs';
import { wasmBindings, instrumentWasmSource } from './wasm-bindings.mjs';
const revision = 'exact-source-revision';
const digest = 'f'.repeat(64);
function fixture(name) {
  const expected = algorithms[name];
  const key = `${expected.module}.${expected.name ?? '__nuppConst_decodeFused_123abc'}`;
  return { algorithm: name, revision, logical: name === 'fused-json' ? 'decodeEager' : undefined,
    variant: name === 'fused-json' ? 2 : undefined, oracleSources: expected.oracle.map((path) => ({path, sha256: digest})),
    execution: { ok: true, executionPath: 'simd', tier: 'simd128', cases: expected.cases,
      nativeCalls: 100, probes: 1, appSha256: digest, randomFingerprint: expected.randomFingerprint, symbols: {[key]: 'actual_symbol'},
      entries: [{key, symbol: 'actual_symbol', unit: 'actual_unit', entryMode: name === 'fused-json' ? 'builder' : 'kernel'}],
      artifacts: [{unit: 'actual_unit', tier: 'simd128', sha256: digest}],
      hostArtifacts: ['nupp-app.mjs', 'nupp-app.wasm'].map((name) => ({name, sha256: digest})) } };
}
const rows = () => Object.keys(algorithms).map(fixture);
test('all four original corpora require returned compiled calls at one revision', () => {
  assert.equal(summarizeAlgorithms(rows(), revision).full_wasm_algorithm_inventory_complete, true);
});
for (const [name, change] of [
  ['missing algorithm', (values) => values.pop()],
  ['duplicate algorithm', (values) => { values[1] = values[0]; }],
  ['wrong revision', (values) => { values[0].revision = 'old'; }],
  ['interpreter-only execution', (values) => { values[0].execution.nativeCalls = 0; }],
  ['different random stream', (values) => { values[0].execution.randomFingerprint = 'park-miller:1:1:16807'; }],
  ['smaller corpus', (values) => { values[0].execution.cases--; }],
  ['wrong tier', (values) => { values[0].execution.tier = 'scalar'; }],
  ['wrong registered entry', (values) => { values[0].execution.entries[0].key = 'other.entry'; }],
  ['missing compiled unit', (values) => { values[0].execution.artifacts[0].unit = 'other'; }],
  ['missing original corpus', (values) => { values[0].oracleSources = []; }],
  ['wrong fused variant', (values) => { values[3].variant = 0; }],
  ['wrong fused logical operation', (values) => { values[3].logical = 'decodePull'; }],
  ['wrong fused entry mode', (values) => { values[3].execution.entries[0].entryMode = 'kernel'; }],
]) test(`${name} cannot complete algorithm acceptance`, () => {
  const values = rows(); change(values);
  assert.throws(() => summarizeAlgorithms(values, revision));
});
test('private kernel and const-specialized builder bindings preserve actual identities', () => {
  const source = `
local __nuppWasm_ks_privateUnit = assert(__nuppWasm_ks_privateRegistry["unit-one"], "unit")
local __nuppWasm_ks_privateNative = assert(__nuppWasm_ks_privateUnit["ks_private"], "Wasm AOT kernel validPrefix is not registered")
local __nuppWasm_ks_specializedUnit = assert(__nuppWasm_ks_specializedRegistry [ "unit-two" ], "unit")
local __nuppWasm_ks_specializedNative = assert(__nuppWasm_ks_specializedUnit [ "ks_specialized" ], "Wasm AOT builder decodeFused_const_123 is not registered")`;
  assert.deepEqual(wasmBindings(source), [
    {symbol: 'ks_private', name: 'validPrefix', unit: 'unit-one', entryMode: 'kernel'},
    {symbol: 'ks_specialized', name: 'decodeFused_const_123', unit: 'unit-two', entryMode: 'builder'},
  ]);
});
test('a binding without its actual unit is refused', () => {
  assert.throws(() => wasmBindings('local __nuppWasm_ks_badNative = assert(__nuppWasm_ks_badUnit["ks_bad"], "Wasm AOT builder decode is not registered")'));
});

test('archived oracle bytes must match both the recorded hash and current source', () => {
  const directory = mkdtempSync(path.join(tmpdir(), 'nupp-wasm-algorithm-oracle-'));
  try {
    const root = path.join(directory, 'repo'), project = path.join(directory, 'bundle');
    const original = algorithms.utf8simd.oracle[0], content = 'the shared independent corpus';
    for (const relative of algorithms.utf8simd.oracle) {
      for (const file of [path.join(root, relative), path.join(project, 'oracle-sources', relative)]) {
        mkdirSync(path.dirname(file), {recursive: true}); writeFileSync(file, content);
      }
    }
    const source = path.join(root, original), copy = path.join(project, 'oracle-sources', original);
    const corpus = {algorithm: 'utf8simd', oracleSources: algorithms.utf8simd.oracle.map((file) => ({path: file,
      sha256: createHash('sha256').update(content).digest('hex')}))};
    verifyOriginalSources(corpus, 'utf8simd', root, project);
    writeFileSync(copy, 'a smaller corpus');
    assert.throws(() => verifyOriginalSources(corpus, 'utf8simd', root, project));
    writeFileSync(copy, content); writeFileSync(source, 'a different revision');
    assert.throws(() => verifyOriginalSources(corpus, 'utf8simd', root, project));
  } finally { rmSync(directory, {recursive: true}); }
});

test('owned algorithms have one dedicated job outside the type-width matrix', () => {
  const workflow = readFileSync(new URL('../../.github/workflows/simd-conformance.yml', import.meta.url), 'utf8');
  const block = workflow.match(/^  wasm-algorithms:\n([\s\S]*?)(?=^  [a-z][a-z-]*:|$(?![\s\S]))/m)?.[1];
  assert.ok(block, 'dedicated algorithm job is required');
  assert.ok(!block.includes('matrix:'), 'algorithm job must not be multiplied by type or width');
  assert.equal(workflow.split('run: tests/simd/run-wasm-algorithms.sh').length - 1, 1);
  assert.ok(block.includes('run: tests/simd/run-wasm-algorithms.sh'));
});

test('registrar instrumentation preserves arbitrary bytes in Lua literals', () => {
  const binding = 'local __nuppWasm_ks_bytesUnit=assert(__nuppWasm_ks_bytesRegistry["byte-unit"],"unit")\n' +
    'local __nuppWasm_ks_bytesNative=assert(__nuppWasm_ks_bytesUnit["ks_bytes"],"Wasm AOT kernel scan is not registered")\n';
  const source = Buffer.concat([Buffer.from(binding + 'return "'), Buffer.from([0x00, 0x80, 0xff]), Buffer.from('"')]);
  assert.deepEqual(wasmBindings(source.toString('utf8')), [
    {symbol: 'ks_bytes', name: 'scan', unit: 'byte-unit', entryMode: 'kernel'},
  ]);
  const prefix = 'local entry=(function()\n', suffix = '\nend)()';
  const instrumented = instrumentWasmSource(source, prefix, suffix);
  assert.deepEqual(instrumented.subarray(Buffer.byteLength(prefix), -Buffer.byteLength(suffix)), source);
  assert.throws(() => instrumentWasmSource(source.toString('utf8'), prefix, suffix));
});
