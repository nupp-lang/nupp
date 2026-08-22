import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";
import test from "node:test";

import { createCompilerHost } from "../src/wasm-runtime.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const dist = path.join(root, "dist");
const manifest = JSON.parse(readFileSync(path.join(dist, "nupp-playground-assets.json"), "utf8"));
const moduleUrl = pathToFileURL(path.join(dist, manifest.hostModule)).href;
const wasmUrl = pathToFileURL(path.join(dist, manifest.hostWasm)).href;
const compilerUrl = pathToFileURL(path.join(dist, manifest.compiler)).href;
const wasmBinary = readFileSync(path.join(dist, manifest.hostWasm));

function fileFetch(url, mutate = false) {
  const bytes = new Uint8Array(readFileSync(fileURLToPath(url)));
  if (mutate) bytes[bytes.length - 1] ^= 1;
  return Promise.resolve(new Response(bytes));
}

test("runs the native differential corpus through the Wasm host", async () => {
  const host = await createCompilerHost({
    moduleUrl,
    wasmUrl,
    compilerUrl,
    expectedDigest: manifest.compilerSha256,
    wasmBinary,
    fetchImpl: fileFetch,
  });
  const source = "local answer: integer = 42\nreturn answer";
  const actual = {
    check: host.request({
      kind: "check",
      source,
      filename: "differential.nupp",
      options: { strict: true, dialect: "lua51" },
    }),
    compile: host.request({
      kind: "compile",
      source,
      filename: "differential.nupp",
      options: { strict: true, optimize: true, dialect: "lua51" },
    }),
    hover: host.request({
      kind: "hover",
      offset: 7,
      options: { dialect: "lua51" },
    }),
  };
  const temporary = process.env.RUNNER_TEMP || "/tmp";
  const expected = JSON.parse(readFileSync(
    path.join(temporary, "nupp-portable-compiler/portable-compiler-reference.json"),
    "utf8"
  ));
  assert.deepEqual(actual, expected);

  const luajit = host.request({
    kind: "compile",
    source: "const value = 2ULL\nreturn value",
    filename: "luajit-output.nupp",
    options: { dialect: "luajit" },
  });
  assert.match(luajit.code, /2ULL/);
  assert.ok(!luajit.diagnostics.some((diagnostic) => diagnostic.code === "NUPP3005"));
});

test("rejects a compiler asset whose bytes do not match the host", async () => {
  await assert.rejects(
    createCompilerHost({
      moduleUrl,
      wasmUrl,
      compilerUrl,
      expectedDigest: manifest.compilerSha256,
      wasmBinary,
      fetchImpl: (url) => fileFetch(url, true),
    }),
    /SHA-256 mismatch/
  );
});
