import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {copyFileSync, cpSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {digest, verifyGuest} from '../../runtime/luajit/package-assets.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
export function prepareArchive(archive, destination, fixtures, repo = root) {
  archive = path.resolve(archive);
  destination = path.resolve(destination);
  mkdirSync(destination, {recursive:true});
  if (readdirSync(destination).length) throw new Error('Archive verification needs an empty destination');
  const guest = path.join(destination, 'guest'), site = path.join(destination, 'site');
  mkdirSync(guest);
  execFileSync('tar', ['-xzf', archive, '-C', guest]);
  const manifest = verifyGuest(repo, guest);

  // Verify the source identity and inventory inside the distributed archive,
  // rather than accepting a file named matching-source.tar.gz as sufficient.
  const matching = path.join(guest, 'matching-source.tar.gz');
  const unpackedSources = path.join(destination, 'matching');
  mkdirSync(unpackedSources);
  let sourceArchives;
  try {
    execFileSync('tar', ['-xzf', matching, '-C', unpackedSources]);
    const source = path.join(unpackedSources, 'source');
    const inputs = JSON.parse(readFileSync(path.join(source, 'build-inputs.json'), 'utf8'));
    assert.deepEqual(inputs, manifest.inputs, 'Matching sources belong to another guest build');
    for (const name of Object.keys(inputs).filter(name => name.includes('/'))) {
      assert.equal(digest(readFileSync(path.join(source, name))), inputs[name], `Matching source integrity failure: ${name}`);
    }
    for (const name of ['linux.resolved.config', 'seabios.resolved.config']) {
      assert(statSync(path.join(source, name)).isFile(), `Matching sources are missing ${name}`);
    }
    sourceArchives = readdirSync(path.join(source, 'archives')).map(name => `source/archives/${name}`);
    const expected = Object.values(inputs.inputs || {}).sort();
    assert(expected.length > 0, 'Matching sources declare no upstream archives');
    const actual = sourceArchives.map(name => digest(readFileSync(path.join(unpackedSources, name)))).sort();
    assert.deepEqual(actual, expected, 'Matching upstream source archive hashes differ');
  } finally {
    rmSync(unpackedSources, {recursive:true, force:true});
  }

  // The test site and every packaged application consume only extracted runtime
  // assets. The build directory supplies the separately built compiler/oracles.
  cpSync(guest, site, {recursive:true});
  for (const name of ['features.lua', 'smoke.html', 'smoke.mjs', 'compiler.html', 'compiler.mjs',
    'recovery.html', 'recovery.mjs', 'lifecycle.html', 'lifecycle.mjs', 'application.html']) {
    copyFileSync(path.join(repo, 'tests/luajit-browser', name), path.join(site, name));
  }
  for (const name of ['compiler.ljbc', 'compiler-requests.json', 'compiler-expected.json',
    'app-runtime.lua', 'application.mjs', 'application-sources.json']) {
    copyFileSync(path.join(fixtures, name), path.join(site, name));
  }
  const result = {archive, archiveSha256:digest(readFileSync(archive)), buildKey:manifest.buildKey,
    assets:Object.keys(manifest.assets).length, notices:Object.keys(manifest.assets).filter(name => name.startsWith('notices/')),
    sourceArchives, snapshots:manifest.snapshots, guest, site};
  writeFileSync(path.join(destination, 'archive-verification.json'), JSON.stringify(result, null, 2)+'\n');
  return result;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [archive, destination, fixtures] = process.argv.slice(2);
  if (!archive || !destination || !fixtures) throw new Error('usage: prepare-archive.mjs ARCHIVE EMPTY_DIRECTORY FIXTURE_DIRECTORY');
  console.log(JSON.stringify(prepareArchive(archive, destination, fixtures)));
}
