import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync,
  statSync, utimesSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {inputKey, restoreArtifact, saveArtifact, sourceFingerprint} from '../../../scripts/pages-cache.mjs';

const ROOT = fileURLToPath(new URL('../../../', import.meta.url));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
function fixture(t) {
  const repo = mkdtempSync(path.join(tmpdir(), 'nupp-native-pages-cache-'));
  t.after(() => rmSync(repo, {recursive: true, force: true}));
  execFileSync('git', ['init', '-q', repo]);
  function write(name, value) {
    const file = path.join(repo, name);
    mkdirSync(path.dirname(file), {recursive: true});
    writeFileSync(file, value);
  }
  write('.gitignore', '/build/\n/.nupp/\n');
  write('src/main.nupp', 'return true\n');
  write('scripts/pages-cache.mjs', 'recipe\n');
  copyFileSync(path.join(ROOT, 'scripts/vm-cli'), path.join(repo, 'scripts/vm-cli'));
  write('scripts/bootstrap-seeds.json', '{"seed":"one"}\n');
  write('docs/guide.md', '# Guide\n');
  const runtime = Buffer.from('native runtime\n'), image = Buffer.from('nupp.tools.vm.root\n');
  const format = 'nupp-vm-cli-1', runtimeSha256 = hash(runtime), imageSha256 = hash(image);
  const generation = hash(JSON.stringify({format, imageSha256, runtimeSha256}));
  const base = `.nupp/vm-cli/${generation}`;
  write(base + '/runtime', runtime);
  chmodSync(path.join(repo, base, 'runtime'), 0o755);
  write(base + '/compiler.image', image);
  write(base + '/format', format + '\n');
  write(base + '/runtime-identity', runtimeSha256 + '\n');
  write('.nupp/vm-cli/current', generation + '\n');
  write('.nupp/vm-cli/stamp', '');
  const receipt = {format, runtimeSha256, imageSha256, runtimeIdentity: runtimeSha256,
    sourceRead: 'build-start', linked: true, sourceAtInstall: {revision: null, fingerprint: sourceFingerprint(repo)}};
  write(base + '/receipt.json', JSON.stringify(receipt) + '\n');
  return {repo, write, base, generation, receipt};
}

test('Pages keys retain prose reuse and invalidate native, seed, recipe, and new inputs', t => {
  const f = fixture(t), before = inputKey('compiler', f.repo);
  for (const name of ['docs/guide.md', 'docs/public/nupp.css', 'README.md']) f.write(name, 'prose');
  assert.equal(inputKey('compiler', f.repo), before);
  for (const name of ['new-build-input', 'native/new.rs', 'tests/cache.lua', 'host/notices/LICENSE.md']) {
    f.write(name, 'new input');
    assert.notEqual(inputKey('compiler', f.repo), before, name);
    rmSync(path.join(f.repo, name));
    assert.equal(inputKey('compiler', f.repo), before);
  }
  f.write('scripts/bootstrap-seeds.json', '{"seed":"two"}');
  assert.notEqual(inputKey('compiler', f.repo), before);
});

test('The source protocol agrees with the existing native CLI status oracle', t => {
  const f = fixture(t);
  const result = JSON.parse(execFileSync('python3', [path.join(f.repo, 'scripts/vm-cli'), 'status'],
    {cwd: f.repo, encoding: 'utf8'}));
  assert.equal(result.sourceChangedSinceInstall, false);
  assert.equal(result.receipt.sourceAtInstall.fingerprint, sourceFingerprint(f.repo));
});

test('A native snapshot restores the full pair before publishing selection and freshness', t => {
  const f = fixture(t);
  saveArtifact('compiler', f.repo);
  rmSync(path.join(f.repo, '.nupp'), {recursive: true});
  f.write('docs/guide.md', '# Documentation change');
  assert.equal(restoreArtifact('compiler', f.repo), true);
  assert.equal(readFileSync(path.join(f.repo, '.nupp/vm-cli/current'), 'utf8'), f.generation + '\n');
  assert.equal(readFileSync(path.join(f.repo, f.base, 'runtime'), 'utf8'), 'native runtime\n');
  assert.equal(JSON.parse(readFileSync(path.join(f.repo, f.base, 'receipt.json'))).sourceRead, 'build-start');
  assert.ok(statSync(path.join(f.repo, '.nupp/vm-cli/stamp')).mtimeMs > 1000);
  assert.equal(restoreArtifact('compiler', f.repo), true);
});

test('Corrupt, missing, incomplete, and stale native snapshots leave freshness untouched', t => {
  const f = fixture(t), directory = 'build/pages-compiler';
  const stamp = path.join(f.repo, '.nupp/vm-cli/stamp');
  const cases = [
    () => f.write(`${directory}/files/${f.base}/runtime`, 'corrupt'),
    () => rmSync(path.join(f.repo, directory, 'files', f.base, 'compiler.image')),
    () => f.write(directory + '/manifest.json', '{'),
    () => {
      const name = directory + '/manifest.json', manifest = JSON.parse(readFileSync(path.join(f.repo, name)));
      delete manifest.files[f.base + '/receipt.json'];
      f.write(name, JSON.stringify(manifest));
    },
    () => f.write('src/main.nupp', 'edited source'),
    () => f.write('scripts/bootstrap-seeds.json', 'edited seed pins'),
  ];
  for (const damage of cases) {
    f.write('src/main.nupp', 'return true\n');
    f.write('scripts/bootstrap-seeds.json', '{"seed":"one"}\n');
    saveArtifact('compiler', f.repo);
    utimesSync(stamp, new Date(1000), new Date(1000));
    damage();
    assert.equal(restoreArtifact('compiler', f.repo), false);
    assert.equal(statSync(stamp).mtimeMs, 1000);
  }
});

test('A forged file inventory cannot substitute a different runtime or escape the snapshot', t => {
  const f = fixture(t);
  saveArtifact('compiler', f.repo);
  const manifestPath = 'build/pages-compiler/manifest.json';
  const manifest = JSON.parse(readFileSync(path.join(f.repo, manifestPath)));
  const name = f.base + '/runtime', bytes = Buffer.from('another runtime');
  f.write('build/pages-compiler/files/' + name, bytes);
  manifest.files[name] = {...manifest.files[name], sha256: hash(bytes), bytes: bytes.length};
  f.write(manifestPath, JSON.stringify(manifest));
  assert.equal(restoreArtifact('compiler', f.repo), false);
  saveArtifact('compiler', f.repo);
  const escaped = JSON.parse(readFileSync(path.join(f.repo, manifestPath)));
  escaped.files['.nupp/vm-cli/../../../escaped'] = Object.values(escaped.files)[0];
  f.write(manifestPath, JSON.stringify(escaped));
  assert.equal(restoreArtifact('compiler', f.repo), false);
  assert.equal(existsSync(path.join(f.repo, '../escaped')), false);
});

test('Unlinked or installation-only provenance cannot populate the native snapshot', t => {
  const f = fixture(t);
  for (const change of [{linked: false}, {sourceRead: 'install'}, {runtimeIdentity: '0'.repeat(64)}]) {
    f.write(f.base + '/receipt.json', JSON.stringify({...f.receipt, ...change}));
    assert.throws(() => saveArtifact('compiler', f.repo), /identity or source mismatch/);
  }
  assert.equal(existsSync(path.join(f.repo, 'build/pages-compiler/manifest.json')), false);
});

test('Restoration never overwrites a generation that may already be executing', t => {
  const f = fixture(t);
  saveArtifact('compiler', f.repo);
  f.write(f.base + '/runtime', 'existing changed runtime');
  const stamp = path.join(f.repo, '.nupp/vm-cli/stamp');
  utimesSync(stamp, new Date(1000), new Date(1000));
  assert.equal(restoreArtifact('compiler', f.repo), false);
  assert.equal(readFileSync(path.join(f.repo, f.base, 'runtime'), 'utf8'), 'existing changed runtime');
  assert.equal(statSync(stamp).mtimeMs, 1000);
});

test('A source edit during the build cannot publish under the earlier key', t => {
  const f = fixture(t), key = inputKey('compiler', f.repo);
  f.write('src/main.nupp', 'edited during build');
  assert.throws(() => saveArtifact('compiler', f.repo, key), /inputs changed/);
  assert.equal(existsSync(path.join(f.repo, 'build/pages-compiler/manifest.json')), false);
});

test('Only current main can deploy and a failed lookup cannot authorize deployment', t => {
  const f = fixture(t), bin = path.join(f.repo, 'fake-bin');
  const script = path.join(ROOT, '.github/scripts/pages-current.sh');
  f.write('fake-bin/gh', '#!/bin/sh\n[ "$FAIL_LOOKUP" != 1 ] || exit 1\nprintf "%s\\n" "$CURRENT_MAIN"\n');
  chmodSync(path.join(bin, 'gh'), 0o755);
  const output = path.join(f.repo, 'output');
  const env = {...process.env, PATH: bin + path.delimiter + process.env.PATH,
    GITHUB_OUTPUT: output, GITHUB_REPOSITORY: 'fixture/repo', GITHUB_SHA: 'a'.repeat(40)};
  for (const [head, expected] of [['a'.repeat(40), 'true'], ['b'.repeat(40), 'false']]) {
    writeFileSync(output, '');
    execFileSync('sh', [script], {env: {...env, CURRENT_MAIN: head}});
    assert.equal(readFileSync(output, 'utf8'), `deploy=${expected}\n`);
  }
  writeFileSync(output, '');
  assert.throws(() => execFileSync('sh', [script], {env: {...env, FAIL_LOOKUP: '1'}}));
  assert.equal(readFileSync(output, 'utf8'), '');
});
