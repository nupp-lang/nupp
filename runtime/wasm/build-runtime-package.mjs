#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  copyFileSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));

function sha256(file) {
  return createHash("sha256").update(readFileSync(file)).digest("hex");
}

const runtimeSources = [
  "app-runtime.mjs",
  "build-app-host.sh",
  "dylink-runtime.js",
  "nupp_app_host.c",
  "nupp_memory.c",
  "nupp_memory.h",
  "worker-lane.mjs",
  "worker-pool.mjs",
];

export function runtimeSourceDigest() {
  const digest = createHash("sha256");
  for (const name of runtimeSources) {
    digest.update(name);
    digest.update("\0");
    digest.update(readFileSync(path.join(here, name)));
    digest.update("\0");
  }
  return digest.digest("hex");
}

// The Lua tree compiled into the module, digested separately: a check that has
// no tree in hand can still validate the runtime's own sources, and one that
// does must not reuse a module built from a different Lua.
export function luaSourceDigest(luaSource) {
  const digest = createHash("sha256");
  const names = readdirSync(luaSource).filter((name) => /\.[ch]$/.test(name)).sort();
  for (const name of names) {
    digest.update(name);
    digest.update("\0");
    digest.update(readFileSync(path.join(luaSource, name)));
    digest.update("\0");
  }
  return digest.digest("hex");
}

function record(file, name) {
  return {file: name, sha256: sha256(file), bytes: statSync(file).size};
}

// LPeg is pinned by the repository toolchain, which fetches it, checks its
// digest and checks that the notice shipped beside it is the one the source
// carries. A caller does not have to know where that landed.
export function lpegSourceDirectory() {
  return execFileSync(path.join(here, "../../scripts/toolchain"), ["lpeg-source"], {
    encoding: "utf8",
  }).trim();
}

export function buildRuntimePackage(output, luaSource, lpegSource, environment = process.env) {
  const destination = path.resolve(output);
  const source = path.resolve(luaSource);
  const lpeg = path.resolve(lpegSource || lpegSourceDirectory());
  const temporary = mkdtempSync(path.join(os.tmpdir(), "nupp-wasm-runtime-"));
  try {
    const temporaryModule = path.join(temporary, "nupp-app.mjs");
    const hostEnvironment = {...environment};
    if (!hostEnvironment.EMCC && hostEnvironment.NUPP_WASM_CC) {
      hostEnvironment.EMCC = hostEnvironment.NUPP_WASM_CC;
    }
    execFileSync(path.join(here, "build-app-host.sh"), [temporaryModule, source, lpeg], {
      cwd: here,
      env: hostEnvironment,
      stdio: "inherit",
    });
    const temporaryWasm = path.join(temporary, "nupp-app.wasm");
    const moduleDigest = sha256(temporaryModule);
    const wasmDigest = sha256(temporaryWasm);
    const moduleName = `nupp-app-${moduleDigest.slice(0, 16)}.mjs`;
    const wasmName = `nupp-app-${wasmDigest.slice(0, 16)}.wasm`;

    mkdirSync(destination, {recursive: true});
    for (const name of readdirSync(destination)) {
      if (/^nupp-app-[0-9a-f]{16}\.(?:mjs|wasm)$/.test(name) &&
          name !== moduleName && name !== wasmName) {
        rmSync(path.join(destination, name));
      }
    }
    const modulePath = path.join(destination, moduleName);
    const wasmPath = path.join(destination, wasmName);
    copyFileSync(temporaryModule, modulePath);
    copyFileSync(temporaryWasm, wasmPath);
    for (const name of ["app-runtime.mjs", "worker-pool.mjs", "worker-lane.mjs"]) {
      copyFileSync(path.join(here, name), path.join(destination, name));
    }
    copyFileSync(
      path.join(source, "..", "COPYRIGHT"),
      path.join(destination, "LUA-5.1-COPYRIGHT.txt"),
    );
    // LPeg is compiled into the module beside Lua, so its notice travels with
    // the package for the same reason Lua's does.
    copyFileSync(
      path.join(here, "../../host/notices/LPeg-LICENSE.txt"),
      path.join(destination, "LPEG-LICENSE.txt"),
    );

    const manifest = {
      schemaVersion: 1,
      emscripten: "6.0.8",
      sourceSha256: runtimeSourceDigest(),
      luaSha256: luaSourceDigest(source),
      lpegSha256: luaSourceDigest(lpeg),
      module: record(modulePath, moduleName),
      wasm: record(wasmPath, wasmName),
      loader: record(path.join(destination, "app-runtime.mjs"), "app-runtime.mjs"),
      pool: record(path.join(destination, "worker-pool.mjs"), "worker-pool.mjs"),
      lane: record(path.join(destination, "worker-lane.mjs"), "worker-lane.mjs"),
      license: "LUA-5.1-COPYRIGHT.txt",
      lpegLicense: "LPEG-LICENSE.txt",
    };
    writeFileSync(
      path.join(destination, "nupp-wasm-runtime.json"),
      JSON.stringify(manifest, null, 2) + "\n",
    );
    return manifest;
  } finally {
    rmSync(temporary, {recursive: true, force: true});
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  if (process.argv.length !== 4 && process.argv.length !== 5) {
    console.error(
      "usage: build-runtime-package.mjs OUTPUT_DIR LUA_5_1_SOURCE_DIR [LPEG_SOURCE_DIR]");
    process.exit(2);
  }
  buildRuntimePackage(process.argv[2], process.argv[3], process.argv[4]);
}
