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
function execution(shard, family, route) {
  const symbols = {};
  const add = (module, name) => { symbols[`${module}.${name}`] = 'actual-emitted-symbol'; };
  for (const lane of shard.lanes.split(',')) {
    const type = shard.element;
    if (family === 'primitives') {
      for (const [module, name] of [['primitives', 'probe'], ['memory', 'fields'], ['conversions', 'convert'], ['masks', 'masks'],
        ...(lane !== 'preferred' || !['int8', 'uint8', 'int16', 'uint16'].includes(type) ? [['memory', 'indexed']] : []),
        ...(lane !== 'preferred' ? [['transpose', 'transpose']] : []),
        ...(!['float', 'number'].includes(type) ? [['integeredges', 'edges']] : [['bitpatterns', 'bits'], ['bitmemory', 'memorybits'], ['maps', 'mapmath']])]) {
        add(`simd_${module}_${type}_1`, `${name}_${lane}`);
      }
    } else {
      add(`simd_reducers_${type}_1`, `horizontal_${type}_${lane}`);
      if (['number', 'int32', 'uint32', 'int64', 'uint64'].includes(type)) {
        for (let i = 0; i < (type === 'number' ? 14 : 7); i++) add(`simd_masked_reducers_${type}_${lane}`, `masked_case${i}`);
        for (let i = 0; i < (type === 'number' ? 21 : 9); i++) add(`simd_loop_reducers_${type}`, `loop_case${i}`);
      }
    }
  }
  return { ok: true, executionPath: route, cases: 10, probes: Object.keys(symbols).length, nativeCalls: 500, symbols };
}
function run(change) {
  const directory = mkdtempSync(path.join(tmpdir(), 'nupp-simd-aggregate-'));
  try {
    const counted = (route) => ({ ok: true, tier: "simd128", executionPath: route, cases: 100, probes: 3, nativeCalls: 100,
      symbols: { 'simdcounted.counted': 'a', 'simdcounted.literal': 'b', 'simdcounted.vector': 'c' } });
    const summaries = shards.map((shard) => ({ revision, requested_wasm_matrix_complete: true,
      counted: { execution: counted('simd'), scalarC: counted('scalar-c') },
      selection: { types: [shard.element], families: ['primitives', 'reducers'], lanes: shard.lanes.split(',') },
      rows: ['primitives', 'reducers'].map((family) => ({ family, element: shard.element,
        execution: execution(shard, family, 'simd'),
        scalarC: execution(shard, family, 'scalar-c') })) }));
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
for (const family of ['bitpatterns', 'bitmemory', 'masks', 'maps']) {
  for (const route of ['execution', 'scalarC']) {
    test(`missing ${family} ${route} is incomplete`, () => {
      const result = run((rows) => {
        const row = rows.find((summary) => summary.selection.types[0] === 'number').rows[0];
        const execution = row[route];
        for (const key of Object.keys(execution.symbols)) {
          if (key.startsWith(`simd_${family}_`)) delete execution.symbols[key];
        }
        execution.probes = Object.keys(execution.symbols).length;
      });
      assert.notEqual(result.status, 0);
      assert.equal(result.report.full_wasm_inventory_complete, false);
    });
  }
}
for (const [name, change] of [
  ['a wrong counted-runtime tier', (rows) => { rows[0].counted.execution.tier = 'scalar'; }],
  ['missing counted-runtime evidence', (rows) => { delete rows[0].counted; }],
  ['an unexecuted counted scalar route', (rows) => { rows[0].counted.scalarC.nativeCalls = 0; }],
  ['a missing shard', (rows) => rows.pop()],
  ['a duplicate selection', (rows) => { rows[1] = rows[0]; }],
  ['a different revision', (rows) => { rows[0].revision = 'old-revision'; }],
  ['an unexecuted scalar route', (rows) => { rows[0].rows[0].scalarC.nativeCalls = 0; }],
  ['a smaller actual corpus under a full-width selection', (rows) => {
    for (const route of ['execution', 'scalarC']) {
      const execution = rows[0].rows[0][route];
      for (const key of Object.keys(execution.symbols)) if (key.endsWith('_17')) delete execution.symbols[key];
      execution.probes = Object.keys(execution.symbols).length;
    }
  }],
  ['a smaller executed reducer inventory', (rows) => {
    for (const route of ['execution', 'scalarC']) {
      const execution = rows[0].rows[1][route];
      for (const key of Object.keys(execution.symbols)) if (key.endsWith('_17')) delete execution.symbols[key];
      execution.probes = Object.keys(execution.symbols).length;
    }
  }],
  ['a scalar route executing different widths with equal counts', (rows) => {
    const execution = rows[0].rows[0].scalarC;
    execution.symbols = Object.fromEntries(Object.entries(execution.symbols).map(([key, value]) => [key.replace(/_17$/, '_18'), value]));
  }],
  ['a different actual element type', (rows) => {
    rows[0].rows[0].execution.symbols = Object.fromEntries(Object.entries(rows[0].rows[0].execution.symbols).map(([key, value]) => [key.replace('_float_', '_number_'), value]));
  }],
  ['a duplicated family', (rows) => { rows[0].rows[1].family = 'primitives'; }],
]) test(`${name} cannot claim complete coverage`, () => {
  const result = run(change);
  assert.equal(result.status, 1);
  assert.equal(result.report.full_wasm_inventory_complete, false);
});
