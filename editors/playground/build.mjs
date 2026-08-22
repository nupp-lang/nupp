#!/usr/bin/env node
// Builds the UI, the verified portable compiler asset, and its Lua 5.1 Wasm host.
import { build, context } from "esbuild";
import {
  copyFileSync,
  cpSync,
  existsSync,
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
import { lauxlib, lua, to_luastring } from "fengari";

const root = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(root, "../..");
const dist = path.join(root, "dist");
const watch = process.argv.includes("--watch");
const wasmCandidate = process.argv.includes("--wasm-candidate");

function verifyFengariSyntax(filename) {
  const state = lauxlib.luaL_newstate();
  const source = readFileSync(filename, "utf8");
  const status = lauxlib.luaL_loadstring(state, to_luastring(source));
  if (status !== lua.LUA_OK) {
    const message = lua.lua_tojsstring(state, -1);
    lua.lua_close(state);
    throw new Error(`Fengari cannot parse ${filename}: ${message}`);
  }
  lua.lua_close(state);
}

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

  const wasmSource = path.join(root, "wasm");
  const vectorBinary = path.join(repoRoot, "build/playground/sha256-vectors");
  run("cc", [
    "-std=c99",
    "-O2",
    `-I${wasmSource}`,
    path.join(wasmSource, "sha-256.c"),
    path.join(wasmSource, "sha256-vectors.c"),
    "-o",
    vectorBinary,
  ]);
  run(vectorBinary, []);

  const luaSource = process.env.NUPP_LUA51_SOURCE || "/tmp/nupp-portable-compiler/lua-5.1.5/src";
  run(path.join(root, "tools/build-wasm-host.sh"), [
    digest,
    path.join(dist, "nupp-playground.mjs"),
    luaSource,
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
    bytes: {
      compiler: copied.length,
      hostModule: statSync(path.join(dist, "nupp-playground.mjs")).size,
      hostWasm: statSync(path.join(dist, "nupp-playground.wasm")).size,
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

const nodeOnly = ["fs", "path", "os", "child_process", "crypto", "readline-sync", "tmp"];
const fengariShared = {
  ...shared,
  loader: { ...shared.loader, ".lua": "text" },
  alias: Object.fromEntries(
    nodeOnly.map((name) => [name, path.join(root, "src/empty-shim.js")])
  ),
  define: {
    process: "undefined",
    "process.env.FENGARICONF": "undefined",
  },
};

async function runBuild() {
  const manifest = wasmCandidate ? prepareCompilerAsset() : null;
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
    ...fengariShared,
    entryPoints: [path.join(root, "src/worker.js")],
    outfile: path.join(dist, "worker.js"),
  };
  const wasmWorkerOpts = manifest && {
    ...shared,
    entryPoints: [path.join(root, "src/wasm-worker.js")],
    outfile: path.join(dist, "wasm-worker.js"),
    define: {
      __NUPP_COMPILER_ASSET__: JSON.stringify(manifest.compiler),
      __NUPP_COMPILER_SHA256__: JSON.stringify(manifest.compilerSha256),
    },
  };
  const wasmSmokeOpts = manifest && {
    ...shared,
    entryPoints: [path.join(root, "src/wasm-smoke.js")],
    outfile: path.join(dist, "wasm-smoke.js"),
  };
  const wasmBenchmarkOpts = manifest && {
    ...shared,
    entryPoints: [path.join(root, "src/wasm-benchmark.js")],
    outfile: path.join(dist, "wasm-benchmark.js"),
  };

  if (watch) {
    const builds = [
      context(appOpts),
      context(docAppOpts),
      context(workerOpts),
    ];
    if (wasmCandidate) {
      builds.push(
        context(wasmWorkerOpts),
        context(wasmSmokeOpts),
        context(wasmBenchmarkOpts),
      );
    }
    const contexts = await Promise.all(builds);
    await Promise.all(contexts.map((entry) => entry.watch()));
    console.log("watching for changes…");
  } else {
    const builds = [
      build(appOpts),
      build(docAppOpts),
      build(workerOpts),
    ];
    if (wasmCandidate) {
      builds.push(
        build(wasmWorkerOpts),
        build(wasmSmokeOpts),
        build(wasmBenchmarkOpts),
      );
    }
    await Promise.all(builds);
  }

  cpSync(path.join(root, "static"), dist, { recursive: true });

  const bootstrapSource = path.join(repoRoot, "bootstrap/nupp.lua");
  if (!existsSync(bootstrapSource)) {
    throw new Error(`expected ${bootstrapSource} — run from a full checkout`);
  }
  const rocks = path.join(repoRoot, ".rocks");
  run("luajit", [
    path.join(root, "tools/patch-bootstrap-for-browser.lua"),
    bootstrapSource,
    path.join(dist, "nupp-bootstrap.lua"),
  ], {
    env: {
      ...process.env,
      LUA_PATH: `${rocks}/share/lua/5.1/?.lua;${rocks}/share/lua/5.1/?/init.lua;${process.env.LUA_PATH || ";"}`,
      LUA_CPATH: `${rocks}/lib/lua/5.1/?.so;${rocks}/lib/lua/5.1/?.dll;${process.env.LUA_CPATH || ";"}`,
    },
  });
  verifyFengariSyntax(path.join(dist, "nupp-bootstrap.lua"));
  copyFileSync(path.join(root, "README.md"), path.join(dist, "README.md"));
}

runBuild().catch((error) => {
  console.error(error);
  process.exit(1);
});
