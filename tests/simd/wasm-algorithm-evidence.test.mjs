import test from 'node:test';
import assert from 'node:assert/strict';
import { algorithms, summarizeAlgorithms } from './wasm-algorithm-evidence.mjs';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { verifyOriginalSources } from './wasm-algorithm-oracles.mjs';
const revision = 'exact-source-revision';
const digest = 'f'.repeat(64);
function fixture(name) {
  const expected = algorithms[name];
  const key = `${expected.module}.${expected.name ?? '__nuppConst_decodeFused_123abc'}`;
  return { algorithm: name, revision, oracleSources: expected.oracle.map((path) => ({path, sha256: digest})),
    execution: { ok: true, executionPath: 'simd', tier: 'simd128', cases: expected.cases,
      nativeCalls: 100, probes: 1, appSha256: digest, randomFingerprint: expected.randomFingerprint, symbols: {[key]: 'actual_symbol'},
      entries: [{key, symbol: 'actual_symbol', unit: 'actual_unit', entryMode: 'kernel'}],
      artifacts: [{unit: 'actual_unit', tier: 'simd128', sha256: digest}],
      hostArtifacts: ['app-runtime.mjs', 'guest/example/guest-manifest.json'].map((name) => ({name, sha256: digest})) } };
}
const rows = () => Object.keys(algorithms).map(fixture);
test('all three independent-kernel corpora require compiled calls at one revision', () => {
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
]) test(`${name} cannot complete algorithm acceptance`, () => {
  const values = rows(); change(values);
  assert.throws(() => summarizeAlgorithms(values, revision));
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
