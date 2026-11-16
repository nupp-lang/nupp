// These synthetic artifacts test provisioning only; none is loaded as a library.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {spawn, spawnSync} from 'node:child_process';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
function fixture(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'nupp-c-library-pins-'));
  t.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  const write = (name, text, mode) => {
    const file = path.join(directory, name);
    fs.mkdirSync(path.dirname(file), {recursive: true});
    fs.writeFileSync(file, text, mode ? {mode} : undefined);
  };
  for (const name of ['scripts/native-libraries', 'scripts/c-libraries/zlib.sh']) {
    write(name, fs.readFileSync(path.join(root, name)));
  }
  write('scripts/c-libraries/libcurl.sh', '# unrelated recipe\n');
  write('host/notices/zlib-LICENSE.txt', 'test notice\n');
  write('source/zlib-1.4/LICENSE', 'test notice\n');
  fs.mkdirSync(path.join(directory, 'archives'));
  let result = spawnSync('tar', ['-czf', path.join(directory, 'archives/zlib-1.4.tar.gz'), '-C', path.join(directory, 'source'), 'zlib-1.4']);
  assert.equal(result.status, 0);
  write('scripts/toolchain.pins', `ZLIB_VERSION=1.4\nZLIB_SHA256=${digest(path.join(directory, 'archives/zlib-1.4.tar.gz'))}\nZLIB_URL=https://invalid.example/zlib.tar.gz\n`);
  write('tools/uname', '#!/bin/sh\ncase "$1" in -s) echo Linux ;; -m) echo x86_64 ;; *) exit 1 ;; esac\n', 0o755);
  write('tools/cc', '#!/bin/sh\necho test-compiler-1\n', 0o755);
  write('tools/cmake', `#!/bin/sh
if [ "$1" = --version ]; then echo test-cmake-1; exit; fi
echo "$*" >> "$TEST_BUILD_CALLS"
case "$1" in
  -S)
    for option in "$@"; do
      case "$option" in -DCMAKE_INSTALL_PREFIX=*) install=\${option#*=} ;; esac
    done
    mkdir -p "$install/include" "$install/lib"
    echo 'test header, never compiled' > "$install/include/zlib.h"
    echo 'test library, never loaded' > "$install/lib/libz.so"
    ;;
esac
`, 0o755);
  const env = {...process.env, PATH: path.join(directory, 'tools') + path.delimiter + process.env.PATH,
    NUPP_CC: path.join(directory, 'tools/cc'), NUPP_TOOLCHAIN_DIR: path.join(directory, 'cache'),
    NUPP_HOST_SOURCE_DIR: path.join(directory, 'archives'), NUPP_HOST_OFFLINE: '1',
    NUPP_NATIVE_TARGET: 'x86_64-unknown-linux-gnu', TEST_BUILD_CALLS: path.join(directory, 'calls')};
  const args = [path.join(directory, 'scripts/native-libraries'), 'zlib'];
  const run = (extra = {}) => spawnSync('sh', args, {env: {...env, ...extra}, encoding: 'utf8'});
  const success = result => {assert.equal(result.status, 0, result.stderr); return result.stdout.trim();};
  return {directory, write, env, args, run, success};
}

test('verified cold and offline warm reuse performs no build', t => {
  const f = fixture(t), prefix = f.success(f.run());
  const calls = fs.readFileSync(f.env.TEST_BUILD_CALLS, 'utf8');
  assert.match(calls, /--build/);
  fs.rmSync(f.env.NUPP_HOST_SOURCE_DIR, {recursive: true});
  assert.equal(f.success(f.run()), prefix);
  assert.equal(fs.readFileSync(f.env.TEST_BUILD_CALLS, 'utf8'), calls);
});
test('wrong source digest is refused before configure', t => {
  const f = fixture(t);
  fs.writeFileSync(path.join(f.env.NUPP_HOST_SOURCE_DIR, 'zlib-1.4.tar.gz'), 'corrupt');
  const result = f.run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /digest/);
  assert.equal(fs.existsSync(f.env.TEST_BUILD_CALLS), false);
});
test('corrupt cached header or truncated file manifest is refused', t => {
  for (const corrupt of ['include/zlib.h', 'files.sha256']) {
    const f = fixture(t), prefix = f.success(f.run());
    fs.writeFileSync(path.join(prefix, corrupt), '');
    const result = f.run();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /corrupt cache/);
  }
});
test('an unrelated dependency recipe does not invalidate the artifact', t => {
  const f = fixture(t), prefix = f.success(f.run());
  f.write('scripts/c-libraries/libcurl.sh', '# changed unrelated recipe\n');
  assert.equal(f.success(f.run()), prefix);
});
test('a redirected loader alias is refused', {skip: process.platform === 'win32'}, t => {
  const f = fixture(t);
  const tool = fs.readFileSync(path.join(f.directory, 'tools/cmake'), 'utf8');
  f.write('tools/cmake', tool.replace("echo 'test library, never loaded' > \"$install/lib/libz.so\"",
    "echo 'test library, never loaded' > \"$install/lib/libz.so.1\"\n    ln -s libz.so.1 \"$install/lib/libz.so\""), 0o755);
  const prefix = f.success(f.run());
  f.write('foreign.so', 'unverified bytes');
  fs.unlinkSync(path.join(prefix, 'lib/libz.so'));
  fs.symlinkSync(path.join(f.directory, 'foreign.so'), path.join(prefix, 'lib/libz.so'));
  const result = f.run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /corrupt cache/);
});
test('target mismatch and invalid offline flags fail before a build', t => {
  const f = fixture(t);
  assert.match(f.run({NUPP_NATIVE_TARGET: 'aarch64-apple-darwin'}).stderr, /refusing host output/);
  assert.match(f.run({NUPP_HOST_OFFLINE: 'sometimes'}).stderr, /invalid NUPP_HOST_OFFLINE/);
  assert.equal(fs.existsSync(f.env.TEST_BUILD_CALLS), false);
});
test('concurrent producers publish one complete artifact', async t => {
  const f = fixture(t);
  const run = () => new Promise((resolve, reject) => {
    const child = spawn('sh', f.args, {env: f.env});
    let stdout = '', stderr = '';
    child.stdout.on('data', chunk => {stdout += chunk;});
    child.stderr.on('data', chunk => {stderr += chunk;});
    child.on('error', reject);
    child.on('close', status => resolve({status, stdout, stderr}));
  });
  const prefixes = await Promise.all([run(), run(), run()]);
  assert.equal(new Set(prefixes.map(result => f.success(result))).size, 1);
  const calls = fs.readFileSync(f.env.TEST_BUILD_CALLS, 'utf8').split('\n');
  assert.equal(calls.filter(line => line.startsWith('--build ')).length, 1);
});
