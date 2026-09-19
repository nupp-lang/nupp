import {readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {gzipSync} from 'node:zlib';
import path from 'node:path';
const directory = process.argv[2];
const original = JSON.parse(await readFile(path.join(directory, 'guest-manifest.json'), 'utf8'));
for (const mode of ['stale', 'corrupt', 'extent', 'invalid-state']) {
  const manifest = structuredClone(original), snapshot = manifest.snapshots.runner;
  if (mode === 'stale') snapshot.buildKey = 'f'.repeat(64);
  if (mode === 'corrupt') manifest.assets[snapshot.asset].sha256 = '0'.repeat(64);
  if (mode === 'extent') snapshot.uncompressedBytes = 1;
  if (mode === 'invalid-state') {
    const bytes = gzipSync(new Uint8Array(1024));
    snapshot.asset = 'assets/invalid-state.gz';
    snapshot.uncompressedBytes = 1024;
    manifest.assets[snapshot.asset] = {bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex')};
    await writeFile(path.join(directory, snapshot.asset), bytes);
  }
  await writeFile(path.join(directory, `recovery-${mode}.json`), JSON.stringify(manifest));
}
