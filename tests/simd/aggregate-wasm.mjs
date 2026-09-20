// A green subset is not full SIMD-11 coverage: require every declared shard.
import { readFileSync, readdirSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { verifyWasmInventory } from './verify-wasm-inventory.mjs';
const directory = path.resolve(process.argv[2]);
const expected = JSON.parse(readFileSync(process.argv[3], 'utf8'));
const revision = process.argv[4];
mkdirSync(directory, { recursive: true });
const allTypes = ['float', 'number', 'int8', 'uint8', 'int16', 'uint16', 'int32', 'uint32', 'int64', 'uint64'];
const covered = new Map(allTypes.map((element) => [element, new Set()]));
for (const shard of expected) {
  const lanes = covered.get(shard.element);
  if (!lanes) throw new Error(`Unknown requested type: ${shard.element}`);
  for (const value of shard.lanes.split(',')) {
    const width = value === 'preferred' ? value : Number(value);
    if ((width !== 'preferred' && (!Number.isInteger(width) || width < 2 || width > 64)) || lanes.has(width)) {
      throw new Error(`Invalid or duplicate requested width: ${shard.element}/${value}`);
    }
    lanes.add(width);
  }
}
for (const [element, lanes] of covered) {
  if (lanes.size !== 64 || !lanes.has('preferred')) throw new Error(`Incomplete requested widths for ${element}`);
}
const key = (element, lanes) => `${element}:${lanes}`;
const required = new Map(expected.map((row) => [key(row.element, row.lanes), row]));
if (required.size !== expected.length) throw new Error('Duplicate requested Wasm shards');
const found = new Map();
const failures = [];
for (const child of existsSync(directory) ? readdirSync(directory) : []) {
  const summaryPath = path.join(directory, child, 'summary.json');
  if (!existsSync(summaryPath)) continue;
  const summary = JSON.parse(readFileSync(summaryPath, 'utf8'));
  const selection = summary.selection;
  if (!selection || selection.types.length !== 1) {
    failures.push(`${child}: missing exact element selection`);
    continue;
  }
  const identity = key(selection.types[0], selection.lanes.join(','));
  if (!required.has(identity) || found.has(identity)) {
    failures.push(`${child}: unexpected or duplicate shard ${identity}`);
    continue;
  }
  const expectedFamilies = ['primitives', 'reducers'];
  if (summary.revision !== revision || !summary.requested_wasm_matrix_complete ||
      selection.families.length !== 2 || !expectedFamilies.every((family) => selection.families.includes(family)) ||
      summary.rows.length !== 2 || expectedFamilies.some((family) => summary.rows.filter((row) => row.family === family).length !== 1) ||
      summary.rows.some((row) => row.element !== selection.types[0] || !row.execution.ok || !row.scalarC.ok ||
        row.execution.executionPath !== 'simd' || row.scalarC.executionPath !== 'scalar-c' ||
        !(row.execution.nativeCalls > 0) || !(row.scalarC.nativeCalls > 0) ||
        !(row.execution.cases > 0) || !(row.execution.probes > 0) ||
        row.execution.cases !== row.scalarC.cases || row.execution.probes !== row.scalarC.probes)) {
    failures.push(`${child}: incomplete or wrong-head SIMD/scalar-C execution`);
    continue;
  }
  try {
    for (const row of summary.rows) {
      verifyWasmInventory(row.execution, row.family, row.element, selection.lanes);
      verifyWasmInventory(row.scalarC, row.family, row.element, selection.lanes);
    }
  } catch (error) {
    failures.push(`${child}: ${error.message}`);
    continue;
  }
  found.set(identity, { shard: required.get(identity), evidence: summaryPath, summary });
}
const missing = [...required.keys()].filter((identity) => !found.has(identity));
const complete = failures.length === 0 && missing.length === 0;
const report = { schemaVersion: 1, revision, full_wasm_inventory_complete: complete,
  expectedShards: required.size, executedShards: found.size, missing, failures, rows: [...found.values()] };
writeFileSync(path.join(directory, 'full-summary.json'), JSON.stringify(report, null, 2) + '\n');
if (!complete) {
  console.error(JSON.stringify({ missing, failures }, null, 2));
  process.exitCode = 1;
} else {
  console.log(`Complete Wasm SIMD128/scalar-C inventory: ${found.size} shards at ${revision}`);
}
