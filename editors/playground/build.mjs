#!/usr/bin/env node
// Builds the LuaJIT browser UI.
import { build, context } from "esbuild";
import {prepareLuaJIT} from "./tools/prepare-luajit.mjs";
import {
  copyFileSync,
  cpSync,
  mkdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(root, "../..");
const dist = path.join(root, "dist");
const watch = process.argv.includes("--watch");

rmSync(dist, { force: true, recursive: true });
mkdirSync(dist, { recursive: true });

const shared = {
  bundle: true,
  format: "esm",
  target: "es2022",
  sourcemap: true,
  platform: "browser",
  loader: { ".nupp": "text" },
  logLevel: "info",
};

async function runBuild() {
  const manifest = {luajit: await prepareLuaJIT(repoRoot, dist)};
  writeFileSync(path.join(dist, "nupp-playground-assets.json"), JSON.stringify(manifest, null, 2) + "\n");
  const luaJITDefines = {
    __NUPP_LUAJIT_MANIFEST__: JSON.stringify(manifest.luajit.guestManifest),
    __NUPP_LUAJIT_COMPILER__: JSON.stringify(manifest.luajit.compiler),
    __NUPP_LUAJIT_COMPILER_SHA256__: JSON.stringify(manifest.luajit.compilerSha256),
    __NUPP_LUAJIT_COMPILER_BYTES__: JSON.stringify(manifest.luajit.compilerBytes),
    __NUPP_LUAJIT_COMPILER_DECODED_BYTES__: JSON.stringify(manifest.luajit.compilerDecodedBytes),
    __NUPP_LUAJIT_APP_RUNTIME__: JSON.stringify(manifest.luajit.appRuntime),
    __NUPP_LUAJIT_APP_RUNTIME_SHA256__: JSON.stringify(manifest.luajit.appRuntimeSha256),
    __NUPP_LUAJIT_APP_BYTES__: JSON.stringify(manifest.luajit.appRuntimeBytes),
    __NUPP_LUAJIT_APP_DECODED_BYTES__: JSON.stringify(manifest.luajit.appRuntimeDecodedBytes),
  };
  const luaJITWorkerOpts = {...shared, entryPoints: [path.join(root, "src/luajit-worker.js")], outfile: path.join(dist, "worker.js"), define: luaJITDefines};
  const luaJITAppWorkerOpts = {...shared, entryPoints: [path.join(root, "src/luajit-app-worker.js")], outfile: path.join(dist, "app-worker.js"), define: luaJITDefines};
  const appOpts = {
    ...shared,
    entryPoints: [path.join(root, "src/app.js")],
    outfile: path.join(dist, "app.js"),
  };
  const docAppOpts = {
    ...shared,
    entryPoints: [path.join(root, "src/doc-app.js")],
    outfile: path.join(dist, "doc-app.js"),
  };
  if (watch) {
    const builds = [
      context(appOpts),
      context(docAppOpts),
      context(luaJITWorkerOpts),
      context(luaJITAppWorkerOpts),
    ];
    const contexts = await Promise.all(builds);
    await Promise.all(contexts.map((entry) => entry.watch()));
    console.log("watching for changes…");
  } else {
    const builds = [
      build(appOpts),
      build(docAppOpts),
      build(luaJITWorkerOpts),
      build(luaJITAppWorkerOpts),
    ];
    await Promise.all(builds);
  }

  cpSync(path.join(root, "static"), dist, { recursive: true });
  copyFileSync(path.join(root, "README.md"), path.join(dist, "README.md"));
}

runBuild().catch((error) => {
  console.error(error);
  process.exit(1);
});
