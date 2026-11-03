import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { algorithms, summarizeAlgorithms } from './wasm-algorithm-evidence.mjs';
const directory = path.resolve(process.argv[2]);
const revision = readFileSync(path.join(directory, 'revision.txt'), 'utf8').trim();
const expectedRevision = process.argv[3];
const rows = [], failures = [];
if (!expectedRevision || revision !== expectedRevision) failures.push('Algorithm output is not from the requested source revision');
for (const name of Object.keys(algorithms)) {
  try { rows.push(JSON.parse(readFileSync(path.join(directory, name, 'algorithm-result.json'), 'utf8'))); }
  catch (error) { failures.push(`${name}: ${error.message}`); }
}
let report;
try {
  if (failures.length) throw new Error('Not every algorithm produced execution evidence');
  report = summarizeAlgorithms(rows, expectedRevision);
} catch (error) {
  failures.push(error.message);
  report = { schemaVersion: 1, revision, full_wasm_algorithm_inventory_complete: false, rows, failures };
  process.exitCode = 1;
}
writeFileSync(path.join(directory, 'summary.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ complete: report.full_wasm_algorithm_inventory_complete, algorithms: rows.length, failures }));
