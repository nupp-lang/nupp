import { readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { algorithms, verifyAlgorithm } from './wasm-algorithm-evidence.mjs';
import { verifyOriginalSources } from './wasm-algorithm-oracles.mjs';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const [name, projectArg, hostArg, sourceRootArg] = process.argv.slice(2);
const sourceRoot = sourceRootArg ? path.resolve(sourceRootArg) : root;
const project = path.resolve(projectArg);
const expected = algorithms[name];
if (!expected) throw new Error(`Unknown algorithm: ${name}`);
const corpus = JSON.parse(readFileSync(path.join(project, 'corpus.json'), 'utf8'));
verifyOriginalSources(corpus, name, sourceRoot, project);
const execution = spawnSync(process.execPath, [path.join(root, 'tests/simd/run-wasm.mjs'), project, path.resolve(hostArg)],
  { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
writeFileSync(path.join(project, 'registrar-execution.log'), (execution.stdout ?? '') + (execution.stderr ?? ''));
if (execution.error) throw execution.error;
if (execution.status !== 0) throw new Error(`Algorithm execution failed; see ${project}/registrar-execution.log`);
const revision = spawnSync('git', ['rev-parse', 'HEAD'], { cwd: sourceRoot, encoding: 'utf8' });
if (revision.status !== 0) throw new Error('Cannot identify algorithm source revision');
const report = { schemaVersion: 1, algorithm: name, revision: revision.stdout.trim(), oracleSources: corpus.oracleSources,
  compiler: corpus.compiler, logical: corpus.logical, variant: corpus.variant,
  execution: JSON.parse(readFileSync(path.join(project, 'result.json'), 'utf8')) };
verifyAlgorithm(report, name, report.revision);
writeFileSync(path.join(project, 'algorithm-result.json'), JSON.stringify(report, null, 2) + '\n');
console.log(`${name}: ${report.execution.cases} corpus cases, ${report.execution.nativeCalls} returned Wasm calls`);
