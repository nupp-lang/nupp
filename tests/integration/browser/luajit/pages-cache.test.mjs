import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync,
  statSync, utimesSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {inputKey, restoreArtifact, saveArtifact} from '../../../../scripts/pages-cache.mjs';

function fixture(t) {
  const repo = mkdtempSync(path.join(tmpdir(), 'nupp-pages-cache-'));
  t.after(() => rmSync(repo, {recursive: true, force: true}));
  execFileSync('git', ['init', '-q', repo]);
  function write(name, value) {
    const file = path.join(repo, name);
    mkdirSync(path.dirname(file), {recursive: true});
    writeFileSync(file, value);
  }
  write('.gitignore', '/build/\n/editors/playground/dist/\n');
  write('src/main.nupp', 'return true\n');
  write('runtime/luajit/bridge.lua', 'guest\n');
  write('scripts/pages-cache.mjs', 'recipe\n');
  write('docs/guide.md', '# Guide\n');
  write('editors/playground/src/app.js', 'frontend\n');
  write('build/nupp/tools/main.lua', 'compiler\n');
  write('build/io.lua', 'dependency\n');
  write('build/lib/libnupp_native_dev.so', 'native provider\n');
  write('build/.nupp-complete', '');
  write('build/.nupp-state.json', JSON.stringify({targets: {compiler: ['build/nupp/tools/main.lua', 'build/io.lua']}}));
  return {repo, write};
}

test('Pages keys separate prose, frontend, compiler, and guest inputs', t => {
  const f = fixture(t), key = kind => inputKey(kind, f.repo);
  const before = Object.fromEntries(['compiler', 'playground', 'guest'].map(kind => [kind, key(kind)]));
  f.write('docs/guide.md', '# Updated\n');
  f.write('docs/public/nupp.css', 'body {}');
  f.write('README.md', 'Project prose');
  for (const kind of Object.keys(before)) assert.equal(key(kind), before[kind], kind);
  f.write('editors/playground/src/app.js', 'changed frontend');
  assert.notEqual(key('playground'), before.playground);
  assert.equal(key('compiler'), before.compiler);
  assert.equal(key('guest'), before.guest);
  const frontend = key('playground');
  f.write('src/main.nupp', 'return false\n');
  assert.notEqual(key('compiler'), before.compiler);
  assert.notEqual(key('playground'), frontend);
  assert.equal(key('guest'), before.guest, 'compiler edits retain the kernel/BIOS cache');
  f.write('runtime/luajit/bridge.lua', 'changed guest');
  assert.notEqual(key('guest'), before.guest);
});

test('New inputs, deletions, pins, recipes, and carried resources invalidate artifacts', t => {
  const f = fixture(t);
  for (const name of ['new-build-input', 'src/new.nupp', 'scripts/toolchain.pins',
    'tests/cache.lua', 'tests/new-carried-resource', 'host/notices/LICENSE.md', 'editors/playground/README.md']) {
    const before = inputKey('playground', f.repo);
    f.write(name, 'new input');
    assert.notEqual(inputKey('playground', f.repo), before, name);
    rmSync(path.join(f.repo, name));
    assert.equal(inputKey('playground', f.repo), before, name + ' removal');
  }
  execFileSync('git', ['add', '.'], {cwd: f.repo});
  const before = inputKey('playground', f.repo);
  rmSync(path.join(f.repo, 'src/main.nupp'));
  assert.notEqual(inputKey('playground', f.repo), before, 'tracked deletion');
});

test('Snapshot driver and browser-version changes invalidate snapshots without rebuilding the kernel', t => {
  const f = fixture(t), guest = inputKey('guest', f.repo);
  for (const name of ['bench/luajit-browser/run-browser.mjs', 'editors/playground/package-lock.json']) {
    const snapshot = inputKey('snapshots', f.repo), playground = inputKey('playground', f.repo);
    f.write(name, 'changed snapshot input');
    assert.notEqual(inputKey('snapshots', f.repo), snapshot);
    assert.notEqual(inputKey('playground', f.repo), playground);
    assert.equal(inputKey('guest', f.repo), guest);
  }
});

test('A verified compiler restores a fresh checkout and repairs only its freshness timestamps', t => {
  const f = fixture(t);
  saveArtifact('compiler', f.repo);
  const old = new Date(1000);
  utimesSync(path.join(f.repo, 'src/main.nupp'), new Date(), new Date());
  for (const name of ['build/nupp/tools/main.lua', 'build/io.lua', 'build/lib', 'build/.nupp-state.json', 'build/.nupp-complete'])
    rmSync(path.join(f.repo, name), {recursive: true, force: true});
  f.write('docs/guide.md', '# A docs-only change');
  assert.equal(restoreArtifact('compiler', f.repo), true);
  assert.equal(readFileSync(path.join(f.repo, 'build/io.lua'), 'utf8'), 'dependency\n');
  assert.ok(statSync(path.join(f.repo, 'build/.nupp-complete')).mtimeMs > old.getTime());
  assert.ok(statSync(path.join(f.repo, 'build/lib/libnupp_native_dev.so')).mtimeMs > old.getTime());
  assert.equal(restoreArtifact('compiler', f.repo), true);
});

test('Corrupt, missing, incomplete, and stale compiler artifacts do not advance freshness', t => {
  const f = fixture(t), directory = 'build/pages-compiler';
  const stamp = path.join(f.repo, 'build/.nupp-complete');
  const cases = [
    () => f.write(directory + '/files/build/lib/libnupp_native_dev.so', 'corrupt bytes'),
    () => rmSync(path.join(f.repo, directory, 'files/build/io.lua')),
    () => f.write(directory + '/manifest.json', '{'),
    () => {
      const name = directory + '/manifest.json';
      const manifest = JSON.parse(readFileSync(path.join(f.repo, name), 'utf8'));
      delete manifest.files['build/io.lua'];
      f.write(name, JSON.stringify(manifest));
    },
    () => f.write('src/main.nupp', 'different source'),
  ];
  for (const damage of cases) {
    f.write('src/main.nupp', 'return true\n');
    saveArtifact('compiler', f.repo);
    utimesSync(stamp, new Date(1000), new Date(1000));
    damage();
    assert.equal(restoreArtifact('compiler', f.repo), false);
    assert.equal(statSync(stamp).mtimeMs, 1000);
  }
  rmSync(path.join(f.repo, directory), {recursive: true});
  assert.equal(restoreArtifact('compiler', f.repo), false);
});

test('Unexpected artifact paths are rejected before writing into the checkout', t => {
  const f = fixture(t);
  saveArtifact('compiler', f.repo);
  const name = 'build/pages-compiler/manifest.json';
  const manifest = JSON.parse(readFileSync(path.join(f.repo, name), 'utf8'));
  manifest.files['build/../../escaped'] = Object.values(manifest.files)[0];
  f.write(name, JSON.stringify(manifest));
  assert.equal(restoreArtifact('compiler', f.repo), false);
  assert.equal(existsSync(path.join(f.repo, '../escaped')), false);
});

test('A source edit during the build cannot publish an artifact under the earlier key', t => {
  const f = fixture(t), key = inputKey('compiler', f.repo);
  f.write('src/main.nupp', 'edited during build');
  assert.throws(() => saveArtifact('compiler', f.repo, key), /inputs changed/);
  assert.equal(existsSync(path.join(f.repo, 'build/pages-compiler/manifest.json')), false);
});

