#!/usr/bin/env node
import {prepareGuest} from './prepare-guest.mjs';
import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync, mkdirSync, copyFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {build} from '../../editors/playground/node_modules/esbuild/lib/main.js';
import {copyGuest, digest} from './package-assets.mjs';
const repo = fileURLToPath(new URL('../../', import.meta.url));
let compilerPrepared = false;
export async function packageBrowserApp({project, target, output, guest}) {
  // A cold checkout otherwise routes build --host through the pinned compiler,
  // which predates that option. Bootstrap the checkout's compiler first.
  if (!compilerPrepared) {
    execFileSync(path.join(repo, 'bin/nupp'), ['build'], {cwd:repo, stdio:'inherit'});
    compilerPrepared = true;
  }
  project = path.resolve(project || '.');
  output = path.resolve(output || path.join(project, 'build/browser'));
  const result = JSON.parse(execFileSync(path.join(repo, 'bin/nupp'), ['build', '--target', target || 'browser', '--host', 'browser', '--json'],
    {cwd: project, encoding: 'utf8', stdio: ['ignore','pipe','inherit']}).trim().split('\n').at(-1));
  if (!result.ok || result.dialect !== 'luajit' || !result.artifact?.endsWith('.lua')) throw new Error('A browser application must be a LuaJIT bundle target');
  guest = await prepareGuest(repo,guest);
  const guestManifest = JSON.parse(readFileSync(path.join(guest, 'guest-manifest.json'), 'utf8'));
  const guestName = `guest/${guestManifest.buildKey}/guest-manifest.json`;
  copyGuest(repo, guest, path.dirname(path.join(output, guestName)));
  const assets = {};
  function record(name) {
    const bytes = readFileSync(path.join(output, name));
    assets[name] = {bytes: bytes.length, sha256: digest(bytes)};
    return name;
  }
  record(guestName);
  const bytes = readFileSync(path.resolve(project, result.artifact));
  const app = `app-${digest(bytes).slice(0,16)}.lua`;
  mkdirSync(output, {recursive: true});
  writeFileSync(path.join(output, app), bytes); record(app);
  const kernels = [];
  if (result.aotManifest) {
    const manifestPath = path.resolve(project,result.aotManifest);
    const built = JSON.parse(readFileSync(manifestPath,'utf8'));
    if (built.schemaVersion !== 3 || built.target !== 'wasm32-unknown-emscripten') throw new Error('Unsupported Wasm build manifest');
    for (const unit of built.units) {
      if (!unit.wasm || !unit.bridge || unit.bridge.abi !== 1 || unit.wasm.split(/[\\/]/).includes('..') || path.isAbsolute(unit.wasm)) throw new Error('Invalid independent Wasm unit');
      const name = `aot/${unit.wasm}`;
      mkdirSync(path.dirname(path.join(output,name)),{recursive:true});
      copyFileSync(path.join(path.dirname(manifestPath),unit.wasm),path.join(output,name));
      record(name);
      kernels.push({file:name,unit:unit.unit,tier:unit.tier,...unit.bridge});
    }
  }
  for (const name of ['app-runtime','worker-lane','browser-worker']) {
    await build({entryPoints:[path.join(repo, `runtime/luajit/${name}.mjs`)], outfile:path.join(output, `${name}.mjs`), bundle:true, format:'esm', platform:'browser', target:'es2022'});
    record(`${name}.mjs`);
  }
  copyFileSync(path.join(repo,'runtime/wasm/browser-entry.mjs'), path.join(output,'nupp-browser-app.mjs'));
  const workers = (result.services || []).some(x => x.service === 'host.workers');
  const manifest = {schema:1, runtime:'luajit-v86', app, guest:guestName, guestBuildKey:guestManifest.buildKey, assets, kernels,
    build:{target, dialect:result.dialect, host:'browser'},
    ...(workers ? {workers:{lane:'worker-lane.mjs', maxLanes:2}} : {}),
    limits:{maxEffects:workers ? 262144 : 256, maxEffectBytes:workers ? 268435456 : 4194304,
      maxResponseBytes:workers ? 268435456 : 8388608, maxStorageValueBytes:1048576, deadlineMs:30000}};
  writeFileSync(path.join(output,'nupp-browser-app.json'), JSON.stringify(manifest,null,2)+'\n');
  return manifest;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2), options = {};
  for (let i=0; i<args.length; i+=2) {
    if (!args[i].startsWith('--') || args[i+1] === undefined) throw new Error('Expected --name VALUE');
    options[args[i].slice(2)] = args[i+1];
  }
  console.log(JSON.stringify(await packageBrowserApp(options),null,2));
}
