import {prepareGuest} from '../../../runtime/luajit/prepare-guest.mjs';
import {gzipSync} from 'node:zlib';
import {copyGuest} from '../../../runtime/luajit/package-assets.mjs';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import path from 'node:path';
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
export async function prepareLuaJIT(repo, dist) {
  const run = (command, args, options = {}) => execFileSync(command, args, {cwd: repo, stdio: 'inherit', ...options});
  const guest = await prepareGuest(repo);
  const manifest = JSON.parse(readFileSync(path.join(guest, 'guest-manifest.json'), 'utf8'));
  const relative = `luajit/${manifest.buildKey}`;
  copyGuest(repo, guest, path.join(dist, relative));
  run(path.join(repo, 'scripts/prelude-image'), ['luajit']);
  run(path.join(repo, 'bin/nupp'), ['build', '--target', 'browserLuaJITApplicationRuntime', '--host', 'browser']);
  const luajit = run(path.join(repo, 'scripts/toolchain'), ['luajit'], {encoding:'utf8', stdio:['ignore','pipe','inherit']}).trim();
  const bundle = path.join(repo, 'build/browser-luajit/nupp-compiler.lua');
  const compiler = run(path.join(luajit, 'bin/luajit'), [path.join(repo, 'editors/playground/tools/dump-compiler.lua'), bundle], {stdio:['ignore','pipe','inherit'], maxBuffer:32 * 1024 * 1024});
  if (compiler.length > 7 * 1024 * 1024) throw new Error('Compiler exceeds the guest startup budget');
  const initialize = readFileSync(path.join(repo, 'build/browser-luajit/nupp-app-runtime.lua'));
  const packedCompiler = gzipSync(compiler, {level:9}), packedApp = gzipSync(initialize, {level:9});
  const compilerDigest = sha(packedCompiler), appDigest = sha(packedApp);
  const compilerName = `nupp-compiler-${compilerDigest.slice(0,16)}.ljbc.gz`;
  const appName = `nupp-luajit-app-${appDigest.slice(0,16)}.lua.gz`;
  writeFileSync(path.join(dist, compilerName), packedCompiler);
  writeFileSync(path.join(dist, appName), packedApp);
  return {guestManifest: `${relative}/guest-manifest.json`, compiler: compilerName,
    compilerSha256: compilerDigest, compilerBytes: packedCompiler.length, compilerDecodedBytes: compiler.length,
    appRuntime: appName, appRuntimeSha256: appDigest, appRuntimeBytes: packedApp.length, appRuntimeDecodedBytes: initialize.length};
}
