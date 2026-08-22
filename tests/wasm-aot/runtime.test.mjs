import assert from "node:assert/strict";
import { createHash, webcrypto } from "node:crypto";
import test from "node:test";

import { runPackagedNuppWasmApp } from "../../runtime/wasm/app-runtime.mjs";

globalThis.crypto ||= webcrypto;

const bytes = new TextEncoder().encode("fixture");
const checksum = createHash("sha256").update(bytes).digest("hex");
const moduleChecksum = "1".repeat(64);

function manifest(overrides = {}) {
  return {
    schemaVersion: 1,
    target: "wasm32-unknown-emscripten",
    runtime: {
      module: {file: `nupp-app-${moduleChecksum.slice(0, 16)}.mjs`, sha256: moduleChecksum, bytes: 1},
      wasm: {file: "nupp-app.wasm", sha256: checksum, bytes: bytes.length},
    },
    app: {file: "app.lua", sha256: checksum, bytes: bytes.length},
    sideModules: [],
    ...overrides,
  };
}

function fetcher(document) {
  return async (url) => {
    if (String(url).endsWith("nupp-browser-app.json")) {
      return new Response(JSON.stringify(document), {status: 200});
    }
    return new Response(bytes, {status: 200});
  };
}

test("packaged applications reject unknown manifest versions", async () => {
  await assert.rejects(
    runPackagedNuppWasmApp("https://example.test/nupp-browser-app.json", {
      fetch: fetcher({...manifest(), schemaVersion: 99}),
    }),
    /unsupported Nupp browser application manifest/,
  );
});

test("packaged application assets cannot escape their directory", async () => {
  await assert.rejects(
    runPackagedNuppWasmApp("https://example.test/nupp-browser-app.json", {
      fetch: fetcher(manifest({app: {file: "../app.lua", sha256: checksum, bytes: bytes.length}})),
    }),
    /app\.file must stay inside/,
  );
});

test("packaged applications verify fetched bytes", async () => {
  await assert.rejects(
    runPackagedNuppWasmApp("https://example.test/nupp-browser-app.json", {
      fetch: fetcher(manifest({app: {file: "app.lua", sha256: "2".repeat(64), bytes: bytes.length}})),
    }),
    /app SHA-256 mismatch/,
  );
});

test("runtime modules use content-addressed filenames", async () => {
  const runtime = manifest().runtime;
  runtime.module.file = "nupp-app.mjs";
  await assert.rejects(
    runPackagedNuppWasmApp("https://example.test/nupp-browser-app.json", {
      fetch: fetcher(manifest({runtime})),
    }),
    /runtime\.module must use its content-addressed filename/,
  );
});
