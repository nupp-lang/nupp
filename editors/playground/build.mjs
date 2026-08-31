#!/usr/bin/env node
// Builds the UI, the verified portable compiler asset, and its Lua 5.1 Wasm host.
import { build, context } from "esbuild";
import {
  copyFileSync,
  cpSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  statSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(root, "../..");
const dist = path.join(root, "dist");
const watch = process.argv.includes("--watch");

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function run(command, args, options = {}) {
  execFileSync(command, args, {
    cwd: options.cwd || repoRoot,
    stdio: "inherit",
    env: options.env || process.env,
  });
}

function prepareCompilerAsset() {
  // This gate builds the bundle, parses and executes it under official Lua
  // 5.1.5 with only the six admitted libraries, and compares its wire output
  // with the normal LuaJIT compiler. The bytes hashed below are those exact
  // bytes: no browser transformation follows the test.
  run(path.join(repoRoot, ".github/scripts/test-portable-compiler.sh"), []);

  const compiler = path.join(repoRoot, "build/playground/nupp-compiler.lua");
  const before = readFileSync(compiler);
  const digest = sha256(before);
  const compilerName = `nupp-compiler-${digest.slice(0, 16)}.lua`;
  for (const entry of readdirSync(dist)) {
    if (/^nupp-compiler-[0-9a-f]+\.lua$/.test(entry) && entry !== compilerName) {
      throw new Error(`stale compiler asset in dist: ${entry}`);
    }
  }
  copyFileSync(compiler, path.join(dist, compilerName));

  // LPeg, for the application host below. The compiler host has no use for it:
  // a `comptime` grammar is compiled by the checker's own PEG front end, and
  // only the matcher it materializes needs an engine to run on.
  const lpegSource = execFileSync(
    path.join(repoRoot, "scripts/toolchain"), ["lpeg-source"], { encoding: "utf8" },
  ).trim();

  const wasmSource = path.join(root, "wasm");
  const luaSource = process.env.NUPP_LUA51_SOURCE || path.join(
    process.env.RUNNER_TEMP || "/tmp",
    "nupp-portable-compiler/lua-5.1.5/src"
  );
  run(path.join(root, "tools/build-wasm-host.sh"), [
    digest,
    path.join(dist, "nupp-playground.mjs"),
    luaSource,
  ], { env: process.env });

  run(path.join(repoRoot, "bin/nupp"), ["build", "--target", "playgroundApplicationRuntime"]);
  const appRuntime = path.join(repoRoot, "build/playground/nupp-app-runtime.lua");
  const appRuntimeBytes = readFileSync(appRuntime);
  const appRuntimeDigest = sha256(appRuntimeBytes);
  const appRuntimeName = `nupp-app-runtime-${appRuntimeDigest.slice(0, 16)}.lua`;
  copyFileSync(appRuntime, path.join(dist, appRuntimeName));
  run(path.join(repoRoot, "runtime/wasm/build-app-host.sh"), [
    path.join(dist, "nupp-runner.mjs"),
    luaSource,
    lpegSource,
  ], { env: process.env });

  const after = readFileSync(compiler);
  if (sha256(after) !== digest || !after.equals(before)) {
    throw new Error("the tested compiler bundle changed while the Wasm host was built");
  }
  const copied = readFileSync(path.join(dist, compilerName));
  if (!copied.equals(before)) {
    throw new Error("the content-hashed compiler asset differs from the tested bundle");
  }

  const manifest = {
    compiler: compilerName,
    compilerSha256: digest,
    hostModule: "nupp-playground.mjs",
    hostWasm: "nupp-playground.wasm",
    appRuntime: appRuntimeName,
    appRuntimeSha256: appRuntimeDigest,
    appHostModule: "nupp-runner.mjs",
    appHostWasm: "nupp-runner.wasm",
    bytes: {
      compiler: copied.length,
      hostModule: statSync(path.join(dist, "nupp-playground.mjs")).size,
      hostWasm: statSync(path.join(dist, "nupp-playground.wasm")).size,
      appRuntime: appRuntimeBytes.length,
      appHostModule: statSync(path.join(dist, "nupp-runner.mjs")).size,
      appHostWasm: statSync(path.join(dist, "nupp-runner.wasm")).size,
    },
  };
  writeFileSync(
    path.join(dist, "nupp-playground-assets.json"),
    JSON.stringify(manifest, null, 2) + "\n"
  );
  return manifest;
}

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
  const manifest = prepareCompilerAsset();
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
  const workerOpts = {
    ...shared,
    entryPoints: [path.join(root, "src/wasm-worker.js")],
    outfile: path.join(dist, "worker.js"),
    define: {
      __NUPP_COMPILER_ASSET__: JSON.stringify(manifest.compiler),
      __NUPP_COMPILER_SHA256__: JSON.stringify(manifest.compilerSha256),
    },
  };
  const appWorkerOpts = {
    ...shared,
    entryPoints: [path.join(root, "src/app-worker.js")],
    outfile: path.join(dist, "app-worker.js"),
    define: {
      __NUPP_APP_RUNTIME_ASSET__: JSON.stringify(manifest.appRuntime),
      __NUPP_APP_RUNTIME_SHA256__: JSON.stringify(manifest.appRuntimeSha256),
    },
  };
  const wasmSmokeOpts = {
    ...shared,
    entryPoints: [path.join(root, "src/wasm-smoke.js")],
    outfile: path.join(dist, "wasm-smoke.js"),
  };

  if (watch) {
    const builds = [
      context(appOpts),
      context(docAppOpts),
      context(workerOpts),
      context(appWorkerOpts),
      context(wasmSmokeOpts),
    ];
    const contexts = await Promise.all(builds);
    await Promise.all(contexts.map((entry) => entry.watch()));
    console.log("watching for changes…");
  } else {
    const builds = [
      build(appOpts),
      build(docAppOpts),
      build(workerOpts),
      build(appWorkerOpts),
      build(wasmSmokeOpts),
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
