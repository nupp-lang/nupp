import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import path from "node:path";
const directory = path.resolve(process.argv[2]);
const rows = [];
for (const family of ["primitives", "reducers"]) {
  let children;
  try { children = readdirSync(path.join(directory, family)); }
  catch (error) { if (error.code === "ENOENT") continue; throw error; }
  for (const element of children.sort()) {
    const result = path.join(directory, family, element, "result.json");
    const execution = JSON.parse(readFileSync(result, "utf8"));
    if (!execution.ok || execution.tier !== "simd128" || !(execution.nativeCalls > 0)) {
      throw new Error(`Incomplete Wasm execution proof: ${result}`);
    }
    rows.push({ family, element, evidence: result, execution });
  }
}
if (!rows.length) throw new Error("No Wasm SIMD128 cases executed");
const report = { schemaVersion: 1,
  revision: readFileSync(path.join(directory, "revision.txt"), "utf8").trim(),
  compilerVersion: readFileSync(path.join(directory, "compiler.txt"), "utf8").trim(),
  runtime: process.version, requested_wasm_matrix_complete: true, rows,
  scope: "The explicitly selected SIMD corpus; native platform/tier coverage is reported separately." };
writeFileSync(path.join(directory, "summary.json"), JSON.stringify(report, null, 2) + "\n");
console.log(`Wasm SIMD128 matrix: ${rows.length} batches executed`);
