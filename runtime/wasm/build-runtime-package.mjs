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

function record(file, name) {
  return {file: name, sha256: sha256(file), bytes: statSync(file).size};
}

export function buildRuntimePackage(output, luaSource, environment = process.env) {
  const destination = path.resolve(output);
  const source = path.resolve(luaSource);
  const temporary = mkdtempSync(path.join(os.tmpdir(), "nupp-wasm-runtime-"));
  try {
    const temporaryModule = path.join(temporary, "nupp-app.mjs");
    const hostEnvironment = {...environment};
    if (!hostEnvironment.EMCC && hostEnvironment.NUPP_WASM_CC) {
      hostEnvironment.EMCC = hostEnvironment.NUPP_WASM_CC;
    }
    execFileSync(path.join(here, "build-app-host.sh"), [temporaryModule, source], {
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
    copyFileSync(path.join(here, "app-runtime.mjs"), path.join(destination, "app-runtime.mjs"));
    copyFileSync(
      path.join(source, "..", "COPYRIGHT"),
      path.join(destination, "LUA-5.1-COPYRIGHT.txt"),
    );

    const manifest = {
      schemaVersion: 1,
      emscripten: "6.0.8",
      module: record(modulePath, moduleName),
      wasm: record(wasmPath, wasmName),
      loader: record(path.join(destination, "app-runtime.mjs"), "app-runtime.mjs"),
      license: "LUA-5.1-COPYRIGHT.txt",
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
  if (process.argv.length !== 4) {
    console.error("usage: build-runtime-package.mjs OUTPUT_DIR LUA_5_1_SOURCE_DIR");
    process.exit(2);
  }
  buildRuntimePackage(process.argv[2], process.argv[3]);
}
