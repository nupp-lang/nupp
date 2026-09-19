// Run against the package's loopback test server after its source build.
import {spawnSync} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
const [directory, baseUrl] = process.argv.slice(2);
if (!directory || !baseUrl) throw new Error('usage: node scripts/browser-snapshot.mjs PACKAGE_DIRECTORY TEST_SERVER_URL');
const root = path.resolve(directory);
const manifestPath = path.join(root, 'guest-manifest.json');
const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
for (const profile of ['runner', 'compiler']) {
  const resultFile = path.join(root, `snapshot-${profile}-capture.json`);
  const result = spawnSync(process.execPath, ['bench/luajit-browser/run-browser.mjs',
    new URL(`snapshot.html?profile=${profile}`, baseUrl).href, resultFile], {stdio: 'inherit'});
  if (result.status !== 0) throw new Error('Snapshot capture failed');
  const capture = JSON.parse(await readFile(resultFile, 'utf8'));
  if (capture.buildKey !== manifest.buildKey || capture.profile !== profile) throw new Error('Snapshot capture belongs to a different guest');
  const bytes = Buffer.from(capture.resources.snapshotBase64, 'base64');
  const name = `assets/snapshot-${profile}.bin.gz`;
  await writeFile(path.join(root, name), bytes);
  manifest.assets[name] = {bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex')};
  (manifest.snapshots ||= {})[profile] = {asset: name, buildKey: manifest.buildKey, guestAbi: manifest.guestAbi,
    memoryMiB: capture.memoryMiB, uncompressedBytes: capture.uncompressedBytes};
  delete capture.resources;
  await writeFile(resultFile, JSON.stringify(capture, null, 2) + '\n');
}
await writeFile(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
