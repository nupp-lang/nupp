#!/usr/bin/env node
// Pages artifacts are reusable only for the same inputs and unchanged outputs.
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {appendFileSync, chmodSync, copyFileSync, existsSync, lstatSync, mkdirSync,
  readFileSync, readdirSync, renameSync, rmSync, utimesSync, writeFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {verifyGuest} from '../runtime/luajit/package-assets.mjs';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const kinds = ['compiler', 'playground', 'guest', 'snapshots'];
function checkedKind(kind) {
  if (!kinds.includes(kind)) throw new Error(`Unknown Pages artifact: ${kind}`);
}

function relevant(kind, name) {
  if (kind === 'snapshots') return relevant('guest', name) ||
    name.startsWith('bench/luajit-browser/') || name === 'editors/playground/package-lock.json' ||
    name === 'scripts/pages-cache.mjs';
  if (kind === 'guest') {
    return /^(native\/|runtime\/luajit\/|host\/notices\/|src\/nupp\/runtime\/vendor\/lunajson\/)/.test(name) ||
      /^(Cargo\.(toml|lock)|rust-toolchain\.toml|\.cargo\/config\.toml|scripts\/toolchain(\.pins)?|scripts\/browser-[^/]+|tests\/integration\/browser\/luajit\/snapshot\.(html|mjs))$/.test(name);
  }
  if (/^(src\/|native\/|runtime\/|host\/|scripts\/|templates\/|rocks\/|tests\/|bench\/|evals\/)/.test(name)) return true;
  if (name.startsWith('editors/')) return kind === 'playground' && name.startsWith('editors/playground/');
  if (/^(docs\/|\.agents\/|\.claude\/|\.codex\/)/.test(name) || name.endsWith('.md')) return false;
  // New, unclassified inputs invalidate both artifacts rather than losing coverage.
  return true;
}

export function inputKey(kind, repo = root) {
  checkedKind(kind);
  const names = [...new Set(execFileSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'],
    {cwd: repo, encoding: 'utf8'}).split('\0').filter(Boolean))].filter(name => relevant(kind, name)).sort();
  const digest = createHash('sha256');
  digest.update(JSON.stringify([1, kind, process.platform, process.arch, process.version,
    process.env.ImageOS, process.env.ImageVersion,
    process.env.NUPP_CC, process.env.NUPP_CXX, process.env.NUPP_CARGO, process.env.NUPP_RUSTC,
    kind === 'compiler' ? path.resolve(repo) : null]));
  for (const name of names) {
    digest.update(name + '\0');
    const file = path.join(repo, name);
    digest.update(existsSync(file) ? `${lstatSync(file).mode & 0o111}:${hash(readFileSync(file))}` : 'missing');
    digest.update('\0');
  }
  return digest.digest('hex');
}

function within(directory, relative) {
  if (typeof relative !== 'string' || !relative || path.isAbsolute(relative) ||
      relative.includes('\\') || relative.split('/').some(part => part === '..' || !part))
    throw new Error('Invalid Pages artifact path');
  return path.join(directory, relative);
}

function filesUnder(directory, relative) {
  const result = [];
  function visit(name) {
    const full = within(directory, name), info = lstatSync(full);
    if (info.isSymbolicLink()) throw new Error(`Pages artifact contains a symlink: ${name}`);
    if (info.isDirectory()) for (const child of readdirSync(full).sort()) visit(name + '/' + child);
    else if (info.isFile()) result.push(name);
    else throw new Error(`Unsupported Pages artifact: ${name}`);
  }
  visit(relative);
  return result;
}

function outputFiles(kind, repo) {
  if (kind === 'playground') return filesUnder(repo, 'editors/playground/dist');
  const state = JSON.parse(readFileSync(path.join(repo, 'build/.nupp-state.json'), 'utf8'));
  if (!Array.isArray(state.targets?.compiler)) throw new Error('No completed compiler target');
  const files = [...state.targets.compiler, 'build/.nupp-state.json', 'build/.nupp-complete',
    ...filesUnder(repo, 'build/lib')];
  if (!files.includes('build/nupp/tools/main.lua')) throw new Error('Compiler entry is missing');
  if (!files.some(name => /^build\/lib\/(lib)?nupp_native_dev\.(so|dll|dylib)$/.test(name)))
    throw new Error('Compiler native provider is missing');
  for (const name of files) if (!name.startsWith('build/')) throw new Error('Compiler output escapes build/');
  return [...new Set(files)].sort();
}

function verifyPlayground(repo, directory) {
  for (const name of ['app.js', 'doc-app.js', 'worker.js', 'app-worker.js', 'index.html'])
    if (!existsSync(within(directory, name))) throw new Error(`Playground is missing ${name}`);
  const assets = JSON.parse(readFileSync(path.join(directory, 'nupp-playground-assets.json'), 'utf8')).luajit;
  if (!assets) throw new Error('Playground has no LuaJIT assets');
  for (const [file, digest, size] of [[assets.compiler, assets.compilerSha256, assets.compilerBytes],
    [assets.appRuntime, assets.appRuntimeSha256, assets.appRuntimeBytes]]) {
    const bytes = readFileSync(within(directory, file));
    if (bytes.length !== size || hash(bytes) !== digest) throw new Error('Playground payload integrity failure');
  }
  verifyGuest(repo, path.dirname(within(directory, assets.guestManifest)));
}

export function saveArtifact(kind, repo = root, expected) {
  checkedKind(kind);
  if (kind !== 'compiler' && kind !== 'playground') throw new Error('The guest uses its existing toolchain cache');
  const key = inputKey(kind, repo);
  if (expected && key !== expected) throw new Error('Pages inputs changed during the build');
  if (kind === 'playground') verifyPlayground(repo, path.join(repo, 'editors/playground/dist'));
  const directory = path.join(repo, 'build/pages-' + kind), staged = directory + '.pending';
  rmSync(staged, {recursive: true, force: true});
  const files = {};
  for (const name of outputFiles(kind, repo)) {
    const source = within(repo, name), destination = within(path.join(staged, 'files'), name);
    const info = lstatSync(source);
    if (!info.isFile()) throw new Error(`Not a regular artifact: ${name}`);
    files[name] = {sha256: hash(readFileSync(source)), bytes: info.size, mode: info.mode & 0o777};
    mkdirSync(path.dirname(destination), {recursive: true});
    copyFileSync(source, destination);
  }
  writeFileSync(path.join(staged, 'manifest.json'), JSON.stringify({schema: 1, kind, key, files}) + '\n');
  rmSync(directory, {recursive: true, force: true});
  // A cache is published only after every output is readable and recorded.
  renameSync(staged, directory);
  return key;
}

export function restoreArtifact(kind, repo = root) {
  checkedKind(kind);
  try {
    const directory = path.join(repo, 'build/pages-' + kind);
    const manifest = JSON.parse(readFileSync(path.join(directory, 'manifest.json'), 'utf8'));
    if (manifest.schema !== 1 || manifest.kind !== kind || manifest.key !== inputKey(kind, repo) ||
        !manifest.files || !Object.keys(manifest.files).length) return false;
    const source = path.join(directory, 'files'), names = Object.keys(manifest.files);
    const required = kind === 'compiler' ? ['build/nupp/tools/main.lua', 'build/.nupp-complete', 'build/.nupp-state.json'] :
      ['editors/playground/dist/nupp-playground-assets.json'];
    if (!required.every(name => names.includes(name))) return false;
    for (const name of names) {
      if (!name.startsWith(kind === 'compiler' ? 'build/' : 'editors/playground/dist/')) return false;
      const file = within(source, name), record = manifest.files[name], info = lstatSync(file);
      if (!info.isFile() || info.size !== record.bytes || hash(readFileSync(file)) !== record.sha256 ||
          !Number.isInteger(record.mode) || record.mode < 0 || record.mode > 0o777) return false;
    }
    if (JSON.stringify(names.sort()) !== JSON.stringify(outputFiles(kind, source).sort())) return false;
    if (kind === 'playground') verifyPlayground(repo, path.join(source, 'editors/playground/dist'));
    for (const name of names) {
      const destination = within(repo, name);
      mkdirSync(path.dirname(destination), {recursive: true});
      copyFileSync(within(source, name), destination);
      chmodSync(destination, manifest.files[name].mode);
    }
    if (kind === 'compiler') {
      // Checkout timestamps are new. Advance freshness only after both proofs.
      const now = new Date();
      for (const name of names.filter(name => name.startsWith('build/lib/')).concat('build/.nupp-complete'))
        utimesSync(within(repo, name), now, now);
    }
    return true;
  } catch {
    return false;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [command, kind] = process.argv.slice(2);
  if (command === 'keys') {
    const outputs = kinds.map(name => `${name}=${inputKey(name)}`).join('\n') + '\n';
    if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, outputs);
    else process.stdout.write(outputs);
  } else if (command === 'restore') {
    const reused = restoreArtifact(kind);
    console.log(`${kind}: ${reused ? 'verified hit' : 'miss'}`);
    if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `reused=${reused}\n`);
  } else if (command === 'save')
    console.log(`${kind}: saved ${saveArtifact(kind, root, process.env[`PAGES_${kind.toUpperCase()}_KEY`])}`);
  else throw new Error('Usage: pages-cache.mjs keys | restore compiler|playground | save compiler|playground');
}
