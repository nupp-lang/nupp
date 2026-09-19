import {gzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync, mkdirSync, copyFileSync, readdirSync} from 'node:fs';
import path from 'node:path';
export const digest = bytes => createHash('sha256').update(bytes).digest('hex');
export function verifyGuest(repo, source) {
  const manifest = JSON.parse(readFileSync(path.join(source, 'guest-manifest.json'), 'utf8'));
  if (manifest.developmentOverlay && process.env.NUPP_BROWSER_DEV !== '1') throw new Error('A development guest overlay is not a production package');
  if (manifest.schema !== 1 || manifest.guestAbi !== 1 || manifest.architecture !== 'i386-linux-musl' ||
      !/^[0-9a-f]{64}$/.test(manifest.buildKey) || !manifest.assets)
    throw new Error('Unsupported guest manifest');
  if (!manifest.snapshots?.runner || !manifest.snapshots?.compiler)
    throw new Error('The guest needs both verified snapshots; run scripts/browser-snapshot.mjs first');
  for (const profile of ['runner', 'compiler']) {
    const snapshot = manifest.snapshots[profile];
    if (snapshot.buildKey !== manifest.buildKey || snapshot.guestAbi !== manifest.guestAbi ||
        snapshot.memoryMiB !== (profile === 'compiler' ? 128 : 64) ||
        snapshot.memoryMiB !== manifest.profiles?.[profile]?.memoryMiB ||
        !Number.isSafeInteger(snapshot.uncompressedBytes) || snapshot.uncompressedBytes <= 0 ||
        snapshot.uncompressedBytes > 256 * 1024 * 1024 || !manifest.assets[snapshot.asset])
      throw new Error(`Invalid guest snapshot: ${profile}`);
  }
  for (const name of ['matching-source.tar.gz', ...readdirSync(path.join(repo, 'host/notices')).map(name => `notices/${name}`)]) {
    if (!manifest.assets[name]) throw new Error(`Guest distribution is missing ${name}`);
  }
  for (const file of ['runtime/luajit/bridge.lua', 'runtime/luajit/guest-init.c', 'runtime/luajit/linux.config', 'runtime/luajit/vm-worker.mjs', 'runtime/luajit/assets.mjs']) {
    if (manifest.inputs?.[file] !== digest(readFileSync(path.join(repo, file)))) throw new Error(`The browser guest is stale: ${file}`);
  }
  for (const [name, record] of Object.entries(manifest.assets)) {
    if (path.isAbsolute(name) || name.split(/[\\/]/).some(part => part === '..' || part === '')) throw new Error('Guest asset path escapes its package');
    if (!record || !Number.isSafeInteger(record.bytes) || record.bytes <= 0 || !/^[0-9a-f]{64}$/.test(record.sha256))
      throw new Error(`Invalid guest asset record: ${name}`);
    const bytes = readFileSync(path.join(source, name));
    if (bytes.length !== record.bytes || digest(bytes) !== record.sha256) throw new Error(`Guest asset integrity failure: ${name}`);
  }
  return manifest;
}
export function copyGuest(repo, source, destination) {
  const manifest = verifyGuest(repo, source);
  for (const name of Object.keys(manifest.assets)) {
    mkdirSync(path.dirname(path.join(destination, name)), {recursive: true});
    copyFileSync(path.join(source, name), path.join(destination, name));
  }
  // Explicit gzip assets work on static hosts without Content-Encoding rules.
  manifest.delivery = {...manifest.delivery};
  for (const name of ['assets/v86.wasm','assets/v86-fallback.wasm']) {
    const bytes = gzipSync(readFileSync(path.join(destination,name)),{level:9});
    const encoded = name+'.gz';
    writeFileSync(path.join(destination,encoded),bytes);
    manifest.assets[encoded] = {bytes:bytes.length,sha256:digest(bytes)};
    manifest.delivery[name] = encoded;
  }
  writeFileSync(path.join(destination, 'guest-manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  return manifest;
}
