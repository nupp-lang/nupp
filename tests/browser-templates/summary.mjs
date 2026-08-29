import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const [plainFile, simdFile, scalarFile] = process.argv.slice(2);
if (!plainFile || !simdFile || !scalarFile) {
  throw new Error("usage: summary.mjs PLAIN SIMD SCALAR");
}

const plain = JSON.parse(readFileSync(plainFile, "utf8"));
const simd = JSON.parse(readFileSync(simdFile, "utf8"));
const scalar = JSON.parse(readFileSync(scalarFile, "utf8"));

assert.equal(plain.ok, true);
assert.equal(plain.result.project, "browser-example");
assert.equal(plain.result.persisted, true);
assert.match(plain.result.digest, /^[0-9a-f]{64}$/);

assert.equal(simd.ok, true);
assert.equal(simd.selected, "simd");
assert.equal(simd.result.tier, "simd128");
assert.equal(simd.result.first, 2);
assert.equal(simd.result.last, 12290);

assert.equal(scalar.ok, true);
assert.equal(scalar.selected, "scalar");
assert.equal(scalar.result.tier, "scalar");
assert.equal(scalar.result.first, simd.result.first);
assert.equal(scalar.result.last, simd.result.last);

process.stdout.write(JSON.stringify({ok: true, plain, simd, scalar}, null, 2) + "\n");
