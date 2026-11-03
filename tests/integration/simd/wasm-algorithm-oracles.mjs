import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { algorithms } from './wasm-algorithm-evidence.mjs';
export function verifyOriginalSources(corpus, name, root, project) {
  const expected = algorithms[name];
  if (!expected || corpus.algorithm !== name || corpus.oracleSources?.length !== expected.oracle.length) {
    throw new Error('Algorithm bundle identity mismatch');
  }
  const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');
  for (const original of expected.oracle) {
    const metadata = corpus.oracleSources.filter((item) => item.path === original);
    const archived = readFileSync(path.join(project, 'oracle-sources', original));
    if (metadata.length !== 1 || metadata[0].sha256 !== digest(archived) ||
        metadata[0].sha256 !== digest(readFileSync(path.join(root, original)))) {
      throw new Error(`Original corpus changed or is missing: ${original}`);
    }
  }
}
