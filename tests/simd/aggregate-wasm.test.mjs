import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const config = path.join(root, '.github/simd-wasm-shards.json');
const shards = JSON.parse(readFileSync(config, 'utf8'));
const revision = 'verified-test-revision';
function run(change) {
  const directory = mkdtempSync(path.join(tmpdir(), 'nupp-simd-aggregate-'));
  try {
    const summaries = shards.map((shard) => ({ revision, requested_wasm_matrix_complete: true,
      selection: { types: [shard.element], families: ['primitives', 'reducers'], lanes: shard.lanes.split(',') },
      rows: ['primitives', 'reducers'].map((family) => ({ family, element: shard.element,
        execution: { ok: true, executionPath: 'simd', cases: 10, probes: 1, nativeCalls: 5 },
        scalarC: { ok: true, executionPath: 'scalar-c', cases: 10, probes: 1, nativeCalls: 5 } })) }));
    change(summaries);
    summaries.forEach((summary, index) => {
      const output = path.join(directory, String(index));
      mkdirSync(output);
      writeFileSync(path.join(output, 'summary.json'), JSON.stringify(summary));
    });
    const result = spawnSync(process.execPath, [path.join(root, 'tests/simd/aggregate-wasm.mjs'), directory, config, revision], { encoding: 'utf8' });
    return { status: result.status, report: JSON.parse(readFileSync(path.join(directory, 'full-summary.json'), 'utf8')) };
  } finally { rmSync(directory, { recursive: true }); }
}
test('all disjoint shards at one revision complete the inventory', () => {
  const result = run(() => {});
  assert.equal(result.status, 0);
  assert.equal(result.report.full_wasm_inventory_complete, true);
  assert.equal(result.report.executedShards, 40);
});
for (const [name, change] of [
  ['a missing shard', (rows) => rows.pop()],
  ['a duplicate selection', (rows) => { rows[1] = rows[0]; }],
  ['a different revision', (rows) => { rows[0].revision = 'old-revision'; }],
  ['an unexecuted scalar route', (rows) => { rows[0].rows[0].scalarC.nativeCalls = 0; }],
  ['a duplicated family', (rows) => { rows[0].rows[1].family = 'primitives'; }],
]) test(`${name} cannot claim complete coverage`, () => {
  const result = run(change);
  assert.equal(result.status, 1);
  assert.equal(result.report.full_wasm_inventory_complete, false);
});
