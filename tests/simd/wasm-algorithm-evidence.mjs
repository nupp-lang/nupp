// Counts and complete PRNG state fingerprints matched independent native and
// byte-preserving Wasm runs before these acceptance values were frozen.
export const algorithms = {
  utf8simd: { module: 'utf8simd', name: 'validPrefix', cases: 199082, randomFingerprint: 'park-miller:31:9704630:1254652296', oracle: ['bench/utf8simd/tests/run.lua', 'tests/simd/corpusmath.lua'] },
  base64simd: { module: 'base64simd', name: 'encode', cases: 80744, randomFingerprint: 'park-miller:20260917:4493157:2096655930', oracle: ['bench/base64simd/tests/run.lua', 'tests/simd/corpusmath.lua'] },
  'simd-json': { module: 'simd_json/indexer', name: 'index', cases: 223519, randomFingerprint: 'park-miller:20260917:453616:447386101', oracle: ['bench/simd-json/tests/index.lua', 'tests/simd/corpusmath.lua'] },
};
const hash = (value) => typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);

export function verifyAlgorithm(report, name, revision) {
  const expected = algorithms[name];
  if (!expected || report?.algorithm !== name || report.revision !== revision) {
    throw new Error(`Missing or wrong-head algorithm evidence: ${name}`);
  }
  const value = report.execution;
  if (!value?.ok || value.executionPath !== 'simd' || value.tier !== 'simd128' ||
      value.cases !== expected.cases || !(value.nativeCalls > 0) || value.probes !== 1 ||
      !hash(value.appSha256) || !Array.isArray(value.entries) || value.entries.length !== 1) {
    throw new Error(`Incomplete algorithm execution: ${name}`);
  }
  if (value.randomFingerprint !== expected.randomFingerprint) {
    throw new Error(`Missing shared random stream identity: ${name}`);
  }
  const [entry] = value.entries;
  const keys = Object.keys(value.symbols ?? {});
  if (keys.length !== 1 || keys[0] !== entry.key || value.symbols[entry.key] !== entry.symbol ||
      !entry.symbol || !entry.unit ||
      entry.key !== `${expected.module}.${expected.name}` || entry.entryMode !== 'kernel') {
    throw new Error(`Wrong returned algorithm entry: ${name}`);
  }
  if (!Array.isArray(value.artifacts) || !value.artifacts.length ||
      value.artifacts.some((unit) => unit.tier !== 'simd128' || !hash(unit.sha256)) ||
      !value.artifacts.some((unit) => unit.unit === entry.unit)) {
    throw new Error(`Missing compiled algorithm identity: ${name}`);
  }
  if (!Array.isArray(value.hostArtifacts) || value.hostArtifacts.length !== 2 ||
      !value.hostArtifacts.some((item) => item.name === 'app-runtime.mjs' && hash(item.sha256)) ||
      !value.hostArtifacts.some((item) => /(?:^|\/)guest-manifest\.json$/.test(item.name) && hash(item.sha256))) {
    throw new Error(`Missing host identity: ${name}`);
  }
  if (!Array.isArray(report.oracleSources) || report.oracleSources.length !== expected.oracle.length ||
      expected.oracle.some((file) => report.oracleSources.filter((item) => item.path === file && hash(item.sha256)).length !== 1)) {
    throw new Error(`Missing original algorithm corpus identity: ${name}`);
  }
  return report;
}

export function summarizeAlgorithms(rows, revision) {
  if (!revision || rows.length !== Object.keys(algorithms).length) throw new Error('Incomplete algorithm inventory');
  for (const name of Object.keys(algorithms)) {
    const matches = rows.filter((row) => row.algorithm === name);
    if (matches.length !== 1) throw new Error(`Missing or duplicate algorithm: ${name}`);
    verifyAlgorithm(matches[0], name, revision);
  }
  return { schemaVersion: 1, revision, full_wasm_algorithm_inventory_complete: true, rows };
}
