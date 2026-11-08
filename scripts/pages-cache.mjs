#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {appendFileSync, chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync,
  readFileSync, readdirSync, renameSync, rmSync, statSync, utimesSync, writeFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const FORMAT = 'nupp-vm-cli-1';
const PACKAGE = ['compiler.image', 'format', 'receipt.json', 'runtime', 'runtime-identity'];
const SOURCE_PATHS = ['src', 'templates', 'native', 'runtime', 'scripts', 'bin', 'nupp.lua',
  'tests/run.lua', 'Cargo.toml', 'Cargo.lock', 'rust-toolchain.toml', '.cargo'];
const order = (a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b));

function checkedKind(kind) {
  if (kind !== 'compiler') throw new Error(`Unknown native Pages artifact: ${kind}`);
}
function listed(repo, paths = []) {
  return [...new Set(execFileSync('git', ['ls-files', '-z', '--cached', '--others',
    '--exclude-standard', '--', ...paths], {cwd: repo, encoding: 'utf8'})
    .split('\0').filter(Boolean))].sort(order);
}
function relevant(name) {
  if (/^(src\/|native\/|runtime\/|host\/|scripts\/|templates\/|tests\/|bench\/|evals\/)/.test(name)) return true;
  if (name.startsWith('editors/')) return false;
  if (/^(docs\/|\.agents\/|\.claude\/|\.codex\/)/.test(name) || name.endsWith('.md')) return false;
  return true;
}
export function inputKey(kind, repo = root) {
  checkedKind(kind);
  const digest = createHash('sha256');
  digest.update(JSON.stringify([2, kind, process.platform, process.arch, process.version,
    process.env.ImageOS, process.env.ImageVersion, process.env.NUPP_CC,
    process.env.NUPP_CXX, process.env.NUPP_CARGO, process.env.NUPP_RUSTC,
    process.env.CC, process.env.CXX, process.env.RUSTFLAGS, process.env.CARGO_ENCODED_RUSTFLAGS,
    process.env.CARGO_BUILD_TARGET, process.env.JIT_OPT, process.env.JIT_REGALLOC, path.resolve(repo)]));
  for (const name of listed(repo).filter(relevant)) {
    const file = path.join(repo, name);
    digest.update(name + '\0');
    digest.update(existsSync(file) ? `${lstatSync(file).mode & 0o111}:${hash(readFileSync(file))}` : 'missing');
    digest.update('\0');
  }
  return digest.digest('hex');
}

// The installed CLI receipt uses this source protocol. Its independent CLI
// status command is the test oracle, including seed pins and native sources.
export function sourceFingerprint(repo = root) {
  const digest = createHash('sha256');
  for (const name of listed(repo, SOURCE_PATHS)) {
    digest.update(name + '\0');
    const file = path.join(repo, name);
    digest.update(existsSync(file) && statSync(file).isFile() ? readFileSync(file) : '<missing>');
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
function regular(directory, name) {
  within(directory, name);
  let file = directory;
  for (const part of name.split('/')) {
    file = path.join(file, part);
    if (lstatSync(file).isSymbolicLink()) throw new Error(`Pages artifact contains a symlink: ${name}`);
  }
  if (!lstatSync(file).isFile()) throw new Error(`Not a regular artifact: ${name}`);
  return file;
}
function makeDirectory(repo, relative) {
  within(repo, relative);
  let directory = repo;
  for (const part of relative.split('/')) {
    directory = path.join(directory, part);
    let info;
    try { info = lstatSync(directory); }
    catch (error) {
      if (error.code !== 'ENOENT') throw error;
      mkdirSync(directory);
      continue;
    }
    if (info.isSymbolicLink() || !info.isDirectory()) throw new Error('Invalid Pages destination');
  }
  return directory;
}
function nativePackage(directory, expectedSource) {
  const generation = readFileSync(regular(directory, '.nupp/vm-cli/current'), 'utf8').trim();
  if (!/^[a-f0-9]{64}$/.test(generation)) throw new Error('Invalid native compiler generation');
  const base = `.nupp/vm-cli/${generation}`;
  if (JSON.stringify(readdirSync(within(directory, base)).sort()) !== JSON.stringify(PACKAGE))
    throw new Error('Incomplete native compiler generation');
  for (const name of PACKAGE) regular(directory, `${base}/${name}`);
  const receipt = JSON.parse(readFileSync(within(directory, `${base}/receipt.json`), 'utf8'));
  const format = readFileSync(within(directory, `${base}/format`), 'utf8').trim();
  const image = readFileSync(within(directory, `${base}/compiler.image`));
  const runtimeSha256 = hash(readFileSync(within(directory, `${base}/runtime`)));
  const imageSha256 = hash(image);
  if (format !== FORMAT || receipt.format !== format || receipt.runtimeSha256 !== runtimeSha256 ||
      receipt.imageSha256 !== imageSha256 || receipt.linked !== true || receipt.sourceRead !== 'build-start' ||
      receipt.sourceAtInstall?.fingerprint !== expectedSource || !image.includes('nupp.tools.vm.root') ||
      !/^[a-f0-9]{64}$/.test(receipt.runtimeIdentity) ||
      readFileSync(within(directory, `${base}/runtime-identity`), 'utf8').trim() !== receipt.runtimeIdentity ||
      hash(JSON.stringify({format, imageSha256, runtimeSha256})) !== generation)
    throw new Error('Native compiler identity or source mismatch');
  regular(directory, '.nupp/vm-cli/stamp');
  return {generation, base, files: ['.nupp/vm-cli/current', '.nupp/vm-cli/stamp', ...PACKAGE.map(name => `${base}/${name}`)].sort()};
}
function publishFile(repo, name, bytes, mode, date) {
  const destination = within(repo, name), pending = destination + `.pages-${process.pid}.pending`;
  try {
    writeFileSync(pending, bytes, {flag: 'wx', mode});
    if (date) utimesSync(pending, date, date);
    renameSync(pending, destination);
  } finally {
    rmSync(pending, {force: true});
  }
}

export function saveArtifact(kind, repo = root, expected) {
  checkedKind(kind);
  const key = inputKey(kind, repo);
  if (expected && key !== expected) throw new Error('Pages inputs changed during the build');
  const source = sourceFingerprint(repo), compiler = nativePackage(repo, source);
  const directory = path.join(repo, 'build/pages-compiler');
  makeDirectory(repo, 'build');
  const staged = mkdtempSync(directory + '.pending-');
  try {
    const files = {};
    for (const name of compiler.files) {
      const file = regular(repo, name), bytes = readFileSync(file), mode = lstatSync(file).mode & 0o777;
      files[name] = {sha256: hash(bytes), bytes: bytes.length, mode};
      const destination = within(path.join(staged, 'files'), name);
      mkdirSync(path.dirname(destination), {recursive: true});
      writeFileSync(destination, bytes, {mode});
    }
    nativePackage(path.join(staged, 'files'), source);
    if (inputKey(kind, repo) !== key) throw new Error('Pages inputs changed during the build');
    writeFileSync(path.join(staged, 'manifest.json'), JSON.stringify({schema: 2, kind, key, files}) + '\n');
    rmSync(directory, {recursive: true, force: true});
    renameSync(staged, directory);
  } finally {
    rmSync(staged, {recursive: true, force: true});
  }
  return key;
}

export function restoreArtifact(kind, repo = root) {
  checkedKind(kind);
  const started = new Date();
  try {
    const directory = path.join(repo, 'build/pages-compiler');
    const manifest = JSON.parse(readFileSync(path.join(directory, 'manifest.json'), 'utf8'));
    if (manifest.schema !== 2 || manifest.kind !== kind || manifest.key !== inputKey(kind, repo) ||
        !manifest.files || !Object.keys(manifest.files).length) return false;
    const source = path.join(directory, 'files'), names = Object.keys(manifest.files).sort();
    for (const name of names) {
      if (!name.startsWith('.nupp/vm-cli/')) return false;
      const file = regular(source, name), record = manifest.files[name], info = lstatSync(file);
      if (info.size !== record.bytes || hash(readFileSync(file)) !== record.sha256 ||
          !Number.isInteger(record.mode) || record.mode < 0 || record.mode > 0o777 ||
          !(record.mode & 0o400) ||
          (process.platform !== 'win32' && name.endsWith('/runtime') && !(record.mode & 0o100))) return false;
    }
    const compiler = nativePackage(source, sourceFingerprint(repo));
    if (JSON.stringify(names) !== JSON.stringify(compiler.files)) return false;
    makeDirectory(repo, '.nupp/vm-cli');
    const destination = within(repo, compiler.base);
    if (existsSync(destination)) {
      for (const name of PACKAGE) {
        const relative = `${compiler.base}/${name}`;
        if (hash(readFileSync(regular(repo, relative))) !== manifest.files[relative].sha256) return false;
      }
      for (const name of PACKAGE) {
        const relative = `${compiler.base}/${name}`;
        chmodSync(within(repo, relative), manifest.files[relative].mode);
      }
    } else {
      mkdirSync(path.dirname(destination), {recursive: true});
      const pending = mkdtempSync(path.join(path.dirname(destination), '.pages-generation-'));
      try {
        for (const name of PACKAGE) {
          const relative = `${compiler.base}/${name}`, target = path.join(pending, name);
          writeFileSync(target, readFileSync(within(source, relative)), {mode: manifest.files[relative].mode});
        }
        renameSync(pending, destination);
      } finally {
        rmSync(pending, {recursive: true, force: true});
      }
    }
    // Selection is published last. Neither a running executable nor its image
    // is overwritten; the stamp predates the input reads that justified it.
    publishFile(repo, '.nupp/vm-cli/stamp', readFileSync(within(source, '.nupp/vm-cli/stamp')),
      manifest.files['.nupp/vm-cli/stamp'].mode, started);
    publishFile(repo, '.nupp/vm-cli/current', Buffer.from(compiler.generation + '\n'),
      manifest.files['.nupp/vm-cli/current'].mode);
    return true;
  } catch {
    return false;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [command, kind] = process.argv.slice(2);
  if (command === 'keys') {
    const value = `compiler=${inputKey('compiler')}\n`;
    if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, value);
    else process.stdout.write(value);
  } else if (command === 'restore') {
    const reused = restoreArtifact(kind);
    console.log(`${kind}: ${reused ? 'verified hit' : 'miss'}`);
    if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `reused=${reused}\n`);
  } else if (command === 'save') {
    console.log(`${kind}: saved ${saveArtifact(kind, root, process.env.PAGES_COMPILER_KEY)}`);
  } else throw new Error('Usage: pages-cache.mjs keys | restore compiler | save compiler');
}
