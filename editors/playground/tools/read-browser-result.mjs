#!/usr/bin/env node
import { readFileSync } from "node:fs";

const [filename, expectedStatus, requireGate] = process.argv.slice(2);
if (!filename || !expectedStatus) {
  throw new Error("usage: read-browser-result.mjs FILE STATUS [--require-gate]");
}
const html = readFileSync(filename, "utf8");
const match = html.match(
  new RegExp(`<pre[^>]*data-status="${expectedStatus}"[^>]*>([\\s\\S]*?)<\\/pre>`)
);
if (!match) throw new Error(`browser result did not reach ${expectedStatus}`);
const result = JSON.parse(match[1]
  .replaceAll("&quot;", '"')
  .replaceAll("&amp;", "&")
  .replaceAll("&lt;", "<")
  .replaceAll("&gt;", ">"));
if (!result.ok) throw new Error(result.error || "browser result failed");
if (requireGate === "--require-gate" && !result.gatePassed) {
  throw new Error(`Wasm timing ratio ${result.ratio.toFixed(3)} exceeds 1.2`);
}
process.stdout.write(JSON.stringify(result, null, 2) + "\n");
