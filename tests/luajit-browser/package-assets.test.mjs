import test from 'node:test';
import assert from 'node:assert/strict';
import childProcess, {execFileSync} from 'node:child_process';
import {syncBuiltinESMExports} from 'node:module';
import {mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {gunzipSync} from 'node:zlib';
import {copyGuest, digest, verifyGuest} from '../../runtime/luajit/package-assets.mjs';
import {prepareArchive} from './prepare-archive.mjs';
import {packageBrowserApp} from '../../runtime/luajit/package-browser-app.mjs';
import {assemblePages} from '../../scripts/build-pages.mjs';

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
    write(repo, relative, name+'\n'); manifest.inputs[relative] = digest(name+'\n');
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

test('Pages assembly preserves hashed runtime notices while decorating site pages', t => {
  const f = fixture(t), docs = path.join(f.root, 'docs'), playground = path.join(f.root, 'playground');
  const output = path.join(f.root, 'pages'), guestPath = path.join('luajit', f.manifest.buildKey);
  const html = '<!doctype html><html><head><title>Fixture</title></head><body>Fixture</body></html>\n';
  f.asset('notices/Rust-dependencies.html', html); f.save();
  const packagedGuest = path.join(playground, guestPath);
  const manifest = copyGuest(f.repo, f.guest, packagedGuest);
  for (const name of ['index.html', 'guide/nested.html']) f.write(docs, name, html);
  for (const name of ['index.html', 'lua51.html']) f.write(playground, name, html);

  assemblePages({docs, playground, output});

  const publishedGuest = path.join(output, 'playground', guestPath);
  assert.deepEqual(verifyGuest(f.repo, publishedGuest), manifest);
  for (const name of ['guest-manifest.json', ...Object.keys(manifest.assets)]) {
    assert.deepEqual(readFileSync(path.join(publishedGuest, name)), readFileSync(path.join(packagedGuest, name)), name);
  }
  for (const name of ['index.html', 'guide/nested.html', 'playground/index.html', 'playground/lua51.html']) {
    const published = readFileSync(path.join(output, name), 'utf8');
    assert.match(published, /<meta property="og:site_name" content="Nupp">/, name);
    assert.match(published, /<meta name="twitter:card" content="summary_large_image">/, name);
  }
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
  f.manifest.inputs['runtime/luajit/bridge.lua'] = digest('bridge.lua\n');
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

test('autocrlf consumer checkouts preserve the Linux runtime input hashes', t => {
  const f = fixture(t), consumer = path.join(f.root, 'consumer-checkout');
  f.write(f.repo, '.gitattributes', readFileSync(new URL('../../.gitattributes', import.meta.url)));
  const attributes = path.join(f.root, 'empty-attributes');
  writeFileSync(attributes, '');
  execFileSync('git', ['init', '--quiet', f.repo]);
  const git = ['-C', f.repo, '-c', `core.attributesFile=${attributes}`];
  execFileSync('git', [...git, '-c', 'core.autocrlf=false', 'add', '.']);
  mkdirSync(consumer);
  execFileSync('git', [...git, '-c', 'core.autocrlf=true', 'checkout-index', '--all', `--prefix=${consumer}/`]);
  assert.equal(verifyGuest(consumer, f.guest).buildKey, f.manifest.buildKey);
});

test('packaged worker pools follow emitted modules across build summary formats', async t => {
  const f = fixture(t), project = path.join(f.root, 'project');
  const repo = fileURLToPath(new URL('../../', import.meta.url));
  for (const name of Object.keys(f.manifest.inputs).filter(name => name.startsWith('runtime/luajit/')))
    f.manifest.inputs[name] = digest(readFileSync(path.join(repo, name)));
  for (const name of readdirSync(path.join(repo, 'host/notices')))
    f.asset(`notices/${name}`, readFileSync(path.join(repo, 'host/notices', name)));
  f.save();
  f.write(project, 'dist/app.lua', 'return true\n');

  let result;
  const compiler = path.join(repo, 'bin/nupp'), originalExec = childProcess.execFileSync;
  childProcess.execFileSync = (command, args) => {
    assert.equal(command, compiler, 'only the compiler process is replaced');
    if (args.length === 1 && args[0] === 'build') return '';
    assert.deepEqual(args, ['build', '--target', 'app', '--host', 'browser', '--json']);
    return JSON.stringify(result)+'\n';
  };
  syncBuiltinESMExports();
  try {
    const cases = [
      {name:'services', written:['build/app/nupp/workers.lua'], services:[{service:'host.workers'}], workers:true},
      {name:'spi', written:['/project/build/app/nupp/workers.lua'], spi:[], workers:true},
      {name:'windows', written:['C:\\project\\build\\app\\nupp\\workers.lua'], spi:[], workers:true},
      {name:'root-module', written:['nupp/workers.lua'], workers:true},
      {name:'unreached', written:['build/not-nupp/workers.lua', 'build/nupp/workers.lua.map', 'build/nupp/workers/builder.lua'],
        services:[{service:'host.workers'}], spi:[], workers:false},
      {name:'no-modules', workers:false},
    ];
    for (const {name, workers, ...summary} of cases) {
      result = {ok:true, dialect:'luajit', artifact:'dist/app.lua', ...summary};
      const output = path.join(f.root, name);
      const manifest = await packageBrowserApp({project, target:'app', output, guest:f.guest});
      assert.deepEqual(manifest.workers, workers ? {lane:'worker-lane.mjs', maxLanes:2} : undefined, name);
      assert.deepEqual(manifest.limits, {
        maxEffects:workers ? 262144 : 256,
        maxEffectBytes:workers ? 268435456 : 4194304,
        maxResponseBytes:workers ? 268435456 : 8388608,
        maxStorageValueBytes:1048576, deadlineMs:30000,
      }, name);
      assert.deepEqual(JSON.parse(readFileSync(path.join(output, 'nupp-browser-app.json'), 'utf8')), manifest, name);
    }
  } finally {
    childProcess.execFileSync = originalExec;
    syncBuiltinESMExports();
  }
});
