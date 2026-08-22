#!/usr/bin/env node
import { brotliCompressSync, constants } from "node:zlib";
import { readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const dist = path.join(root, "dist");
const manifest = JSON.parse(
  readFileSync(path.join(dist, "nupp-playground-assets.json"), "utf8")
);
const compiler = readFileSync(path.join(dist, manifest.compiler));
const brotli = brotliCompressSync(compiler, {
  params: { [constants.BROTLI_PARAM_QUALITY]: 11 },
});

process.stdout.write(JSON.stringify({
  compiler: compiler.length,
  compilerBrotli: brotli.length,
  hostJavaScript: statSync(path.join(dist, manifest.hostModule)).size,
  hostWasm: statSync(path.join(dist, manifest.hostWasm)).size,
}, null, 2) + "\n");
