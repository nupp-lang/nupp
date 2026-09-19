import {gzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import path from 'node:path';
export const digest = bytes => createHash('sha256').update(bytes).digest('hex');
export function copyGuest(repo, source, destination) {
  const manifest = JSON.parse(readFileSync(path.join(source, 'guest-manifest.json'), 'utf8'));
  if (manifest.developmentOverlay && process.env.NUPP_BROWSER_DEV !== '1') throw new Error('A development guest overlay is not a production package');
  if (manifest.schema !== 1 || !manifest.snapshots?.runner || !manifest.snapshots?.compiler)
    throw new Error('The guest needs both verified snapshots; run scripts/browser-snapshot.mjs first');
  for (const file of ['runtime/luajit/bridge.lua', 'runtime/luajit/guest-init.c', 'runtime/luajit/linux.config', 'runtime/luajit/vm-worker.mjs', 'runtime/luajit/assets.mjs']) {
    if (manifest.inputs[file] !== digest(readFileSync(path.join(repo, file)))) throw new Error(`The browser guest is stale: ${file}`);
  }
  for (const [name, record] of Object.entries(manifest.assets)) {
    if (path.isAbsolute(name) || name.split(/[\\/]/).some(part => part === '..' || part === '')) throw new Error('Guest asset path escapes its package');
    const bytes = readFileSync(path.join(source, name));
    if (bytes.length !== record.bytes || digest(bytes) !== record.sha256) throw new Error(`Guest asset integrity failure: ${name}`);
    mkdirSync(path.dirname(path.join(destination, name)), {recursive: true});
    writeFileSync(path.join(destination, name), bytes);
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
