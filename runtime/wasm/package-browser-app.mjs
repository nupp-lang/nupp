#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { buildRuntimePackage } from "./build-runtime-package.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../..");

function argumentsOf(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    const name = argv[index];
    const value = argv[index + 1];
    if (!name?.startsWith("--") || value === undefined) {
      throw new Error("options must be written as --name VALUE");
    }
    values[name.slice(2)] = value;
  }
  return values;
}

function sha256(file) {
  return createHash("sha256").update(readFileSync(file)).digest("hex");
}

function asset(file, name) {
  return {file: name, sha256: sha256(file), bytes: statSync(file).size};
}

function inside(root, relative, label) {
  const parts = typeof relative === "string" ? relative.split("/") : [];
  if (typeof relative !== "string" || relative.length === 0 || relative.includes("\\") ||
      path.isAbsolute(relative) || parts.some((part) => part === "" || part === "." || part === "..")) {
    throw new Error(`${label} escapes its artifact directory`);
  }
  const resolved = path.resolve(root, relative);
  if (resolved !== root && !resolved.startsWith(root + path.sep)) {
    throw new Error(`${label} escapes its artifact directory`);
  }
  return resolved;
}

function buildResult(project, target, environment) {
  const stdout = execFileSync(path.join(repo, "bin/nupp"), ["build", "--target", target, "--json"], {
    cwd: project,
    env: environment,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
  });
  const lines = stdout.trim().split(/\r?\n/);
  const result = JSON.parse(lines[lines.length - 1]);
  if (!result.ok) throw new Error(`Nupp target ${target} did not build`);
  if (result.dialect !== "lua51") {
    throw new Error(`browser application target ${target} must use dialect = "lua51"`);
  }
  if (typeof result.artifact !== "string" || !result.artifact.endsWith(".lua")) {
    throw new Error(`browser application target ${target} must be a bundle with a Lua artifact`);
  }
  return result;
}

function runtimePackage(directory, luaSource, environment) {
  const manifestPath = path.join(directory, "nupp-wasm-runtime.json");
  if (!existsSync(manifestPath)) {
    if (!luaSource) {
      throw new Error("the reusable Wasm runtime is absent; pass --lua-source or set NUPP_LUA51_SOURCE");
    }
    buildRuntimePackage(directory, luaSource, environment);
  }
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  if (manifest.schemaVersion !== 1 || manifest.emscripten !== "6.0.8") {
    throw new Error("unsupported Nupp Wasm runtime package");
  }
  const records = [["module", manifest.module], ["wasm", manifest.wasm], ["loader", manifest.loader]];
  for (const [label, record] of records) {
    const file = inside(directory, record?.file, `runtime ${label}`);
    if (!existsSync(file) || sha256(file) !== record.sha256 || statSync(file).size !== record.bytes) {
      throw new Error(`reusable Wasm runtime ${label} does not match its manifest`);
    }
  }
  return manifest;
}

function cleanOwnedAssets(output) {
  for (const name of readdirSync(output)) {
    if (/^(?:app|nupp-app)-[0-9a-f]{16}\.(?:lua|mjs|wasm)$/.test(name)) {
      rmSync(path.join(output, name));
    }
  }
  rmSync(path.join(output, "aot"), {recursive: true, force: true});
}

function copyRuntime(runtime, output, manifest) {
  for (const record of [manifest.module, manifest.wasm, manifest.loader]) {
    copyFileSync(inside(runtime, record.file, "runtime asset"), path.join(output, record.file));
  }
  copyFileSync(
    inside(runtime, manifest.license, "runtime license"),
    path.join(output, manifest.license),
  );
}

export function packageBrowserApp(options) {
  const project = path.resolve(options.project || ".");
  const target = options.target || "app";
  const output = path.resolve(options.output || path.join(project, "dist/browser"));
  const runtime = path.resolve(options.runtime || path.join(repo, "build/wasm-app-runtime"));
  if (output === project) {
    throw new Error("the browser application output cannot be the project directory");
  }
  if (output === runtime) {
    throw new Error("the browser application output cannot be the reusable runtime directory");
  }
  const luaSource = options.luaSource || process.env.NUPP_LUA51_SOURCE;
  const environment = options.environment || process.env;
  const result = buildResult(project, target, environment);
  const runtimeManifest = runtimePackage(runtime, luaSource, environment);
  mkdirSync(output, {recursive: true});
  cleanOwnedAssets(output);
  copyRuntime(runtime, output, runtimeManifest);

  const artifactPath = path.resolve(project, result.artifact);
  const appDigest = sha256(artifactPath);
  const appName = `app-${appDigest.slice(0, 16)}.lua`;
  const packagedApp = path.join(output, appName);
  copyFileSync(artifactPath, packagedApp);

  const sideModules = [];
  if (result.aotManifest) {
    const manifestPath = path.resolve(project, result.aotManifest);
    const manifestRoot = path.dirname(manifestPath);
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    if (manifest.schemaVersion !== 2 || manifest.target !== "wasm32-unknown-emscripten" ||
        !Array.isArray(manifest.units)) {
      throw new Error("unsupported Wasm AOT unit manifest");
    }
    for (const unit of manifest.units) {
      const source = inside(manifestRoot, unit.wasm, "Wasm AOT unit");
      const name = `aot/${unit.wasm}`;
      const destination = inside(output, name, "packaged Wasm AOT unit");
      mkdirSync(path.dirname(destination), {recursive: true});
      copyFileSync(source, destination);
      sideModules.push({
        ...asset(destination, name),
        registrar: unit.registrar,
        tier: unit.tier,
        unit: unit.unit,
      });
    }
  }

  copyFileSync(path.join(here, "browser-entry.mjs"), path.join(output, "nupp-browser-app.mjs"));
  const manifest = {
    schemaVersion: 1,
    target: "wasm32-unknown-emscripten",
    build: {target, dialect: result.dialect},
    runtime: {module: runtimeManifest.module, wasm: runtimeManifest.wasm},
    app: asset(packagedApp, appName),
    sideModules,
  };
  writeFileSync(
    path.join(output, "nupp-browser-app.json"),
    JSON.stringify(manifest, null, 2) + "\n",
  );
  return manifest;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const values = argumentsOf(process.argv.slice(2));
    const manifest = packageBrowserApp({
      project: values.project,
      target: values.target,
      output: values.output,
      runtime: values.runtime,
      luaSource: values["lua-source"],
    });
    process.stdout.write(JSON.stringify(manifest, null, 2) + "\n");
  } catch (error) {
    console.error(`nupp browser app: ${error.message}`);
    process.exit(1);
  }
}
