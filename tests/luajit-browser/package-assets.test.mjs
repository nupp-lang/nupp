import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {gunzipSync} from 'node:zlib';
import {copyGuest, digest, verifyGuest} from '../../runtime/luajit/package-assets.mjs';
import {prepareArchive} from './prepare-archive.mjs';

function fixture(t) {
  const root = mkdtempSync(path.join(tmpdir(), 'nupp-runtime-package-'));
  t.after(() => rmSync(root, {recursive:true, force:true}));
  const repo = path.join(root, 'repo'), guest = path.join(root, 'guest');
  const write = (directory, name, bytes) => {
    mkdirSync(path.dirname(path.join(directory, name)), {recursive:true});
    writeFileSync(path.join(directory, name), bytes);
  };
  const manifest = {schema:1, guestAbi:1, architecture:'i386-linux-musl', buildKey:'a'.repeat(64),
    profiles:{runner:{memoryMiB:64}, compiler:{memoryMiB:128}}, inputs:{}, assets:{}, snapshots:{}};
  for (const name of ['bridge.lua', 'guest-init.c', 'linux.config', 'vm-worker.mjs', 'assets.mjs']) {
    const relative = `runtime/luajit/${name}`;
    write(repo, relative, name); manifest.inputs[relative] = digest(name);
  }
  write(repo, 'host/notices/LICENSE.txt', 'license');
  manifest.inputs['host/notices/LICENSE.txt'] = digest('license');
  manifest.inputs.inputs = {upstream:digest('upstream')};
  const asset = (name, bytes) => {
    write(guest, name, bytes);
    manifest.assets[name] = {bytes:Buffer.byteLength(bytes), sha256:digest(bytes)};
  };
  for (const profile of ['runner', 'compiler']) {
    const name = `assets/${profile}.gz`; asset(name, profile);
    manifest.snapshots[profile] = {asset:name, buildKey:manifest.buildKey, guestAbi:1,
      memoryMiB:manifest.profiles[profile].memoryMiB, uncompressedBytes:1024};
  }
  asset('assets/v86.wasm', 'wasm'); asset('assets/v86-fallback.wasm', 'fallback');
  asset('notices/LICENSE.txt', 'license');
  const matching = path.join(root, 'matching');
  for (const name of Object.keys(manifest.inputs).filter(name => name.includes('/')))
    write(matching, `source/${name}`, readFileSync(path.join(repo, name)));
  for (const name of ['linux.resolved.config', 'seabios.resolved.config']) write(matching, `source/${name}`, 'config');
  write(matching, 'source/archives/upstream.tar.gz', 'upstream');
  const saveSources = (inputs = manifest.inputs) => {
    write(matching, 'source/build-inputs.json', JSON.stringify(inputs));
    execFileSync('tar', ['-czf', path.join(guest, 'matching-source.tar.gz'), '-C', matching, 'source']);
    asset('matching-source.tar.gz', readFileSync(path.join(guest, 'matching-source.tar.gz')));
  };
  const save = () => write(guest, 'guest-manifest.json', JSON.stringify(manifest));
  saveSources(); save();
  return {root, repo, guest, manifest, asset, save, saveSources, write};
}

test('runtime packages preserve assets and add verified gzip delivery', t => {
  const f = fixture(t), destination = path.join(f.root, 'copy');
  const result = copyGuest(f.repo, f.guest, destination);
  assert.equal(verifyGuest(f.repo, destination).buildKey, f.manifest.buildKey);
  for (const name of ['assets/v86.wasm', 'assets/v86-fallback.wasm']) {
    assert.deepEqual(gunzipSync(readFileSync(path.join(destination, result.delivery[name]))), readFileSync(path.join(f.guest, name)));
  }
  assert.deepEqual(readFileSync(path.join(destination, 'matching-source.tar.gz')), readFileSync(path.join(f.guest, 'matching-source.tar.gz')));
});

test('runtime verification rejects missing notices, matching sources and snapshot assets', t => {
  const f = fixture(t);
  for (const name of ['notices/LICENSE.txt', 'matching-source.tar.gz', f.manifest.snapshots.compiler.asset]) {
    const record = f.manifest.assets[name]; delete f.manifest.assets[name]; f.save();
    assert.throws(() => verifyGuest(f.repo, f.guest), /missing|Invalid guest snapshot/);
    f.manifest.assets[name] = record;
  }
});

test('runtime verification rejects mismatched snapshot identities and extents', t => {
  const f = fixture(t), original = structuredClone(f.manifest.snapshots.compiler);
  for (const patch of [{buildKey:'b'.repeat(64)}, {guestAbi:2}, {memoryMiB:64}, {uncompressedBytes:0}, {uncompressedBytes:256*1024*1024+1}]) {
    f.manifest.snapshots.compiler = {...original, ...patch}; f.save();
    assert.throws(() => verifyGuest(f.repo, f.guest), /Invalid guest snapshot: compiler/);
  }
});

test('runtime verification rejects corrupt assets, stale inputs and escaping paths', t => {
  const f = fixture(t);
  writeFileSync(path.join(f.guest, 'assets/v86.wasm'), 'evil');
  assert.throws(() => verifyGuest(f.repo, f.guest), /integrity failure/);
  f.asset('assets/v86.wasm', 'wasm');
  f.manifest.inputs['runtime/luajit/bridge.lua'] = 'b'.repeat(64); f.save();
  assert.throws(() => verifyGuest(f.repo, f.guest), /stale/);
  f.manifest.inputs['runtime/luajit/bridge.lua'] = digest('bridge.lua');
  f.manifest.assets['../outside'] = {bytes:1, sha256:'0'.repeat(64)}; f.save();
  assert.throws(() => verifyGuest(f.repo, f.guest), /escapes/);
});

function archiveFixture(f) {
  const archive = path.join(f.root, 'runtime.tar.gz'), fixtures = path.join(f.root, 'fixtures');
  for (const name of ['features.lua', 'smoke.html', 'smoke.mjs', 'compiler.html', 'compiler.mjs',
    'recovery.html', 'recovery.mjs', 'lifecycle.html', 'lifecycle.mjs', 'application.html'])
    f.write(f.repo, `tests/luajit-browser/${name}`, name);
  for (const name of ['compiler.ljbc', 'compiler-requests.json', 'compiler-expected.json',
    'app-runtime.lua', 'application.mjs', 'application-sources.json']) f.write(fixtures, name, name);
  execFileSync('tar', ['-czf', archive, '-C', f.guest, '.']);
  return {archive, fixtures};
}

test('archive consumers preserve the shipped manifest and use separately built fixtures', t => {
  const f = fixture(t), a = archiveFixture(f), destination = path.join(f.root, 'consumer');
  const result = prepareArchive(a.archive, destination, a.fixtures, f.repo);
  assert.deepEqual(readFileSync(path.join(result.site, 'guest-manifest.json')), readFileSync(path.join(f.guest, 'guest-manifest.json')));
  assert.equal(readFileSync(path.join(result.site, 'compiler.ljbc'), 'utf8'), 'compiler.ljbc');
  assert.equal(result.sourceArchives.length, 1);
  assert.throws(() => prepareArchive(a.archive, destination, a.fixtures, f.repo), /empty destination/);
});

test('archive consumers reject matching-source payloads from another build', t => {
  const f = fixture(t);
  f.saveSources({...f.manifest.inputs, gcc:'another compiler'}); f.save();
  const a = archiveFixture(f);
  assert.throws(() => prepareArchive(a.archive, path.join(f.root, 'consumer'), a.fixtures, f.repo), /another guest build/);
});

test('archive consumers verify the actual matching-source recipe and upstream bytes', t => {
  for (const name of ['runtime/luajit/bridge.lua', 'archives/upstream.tar.gz']) {
    const f = fixture(t);
    f.write(path.join(f.root, 'matching/source'), name, 'changed source');
    f.saveSources(); f.save();
    const a = archiveFixture(f);
    assert.throws(() => prepareArchive(a.archive, path.join(f.root, 'consumer'), a.fixtures, f.repo), /source integrity|source archive hashes/);
  }
});
