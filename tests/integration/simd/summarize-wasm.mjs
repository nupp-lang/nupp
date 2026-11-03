import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { verifyWasmInventory, verifyCountedRuntime } from "./verify-wasm-inventory.mjs";
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
    const scalarPath = path.join(directory, family, element, "scalar-c/result.json");
    const scalarC = JSON.parse(readFileSync(scalarPath, "utf8"));
    if (!scalarC.ok || scalarC.executionPath !== "scalar-c" || !(scalarC.nativeCalls > 0) ||
        scalarC.cases !== execution.cases || scalarC.probes !== execution.probes) {
      throw new Error(`Incomplete scalar-C Wasm proof: ${scalarPath}`);
    }
    rows.push({ family, element, evidence: result, execution, scalarEvidence: scalarPath, scalarC });
  }
}
if (!rows.length) throw new Error("No Wasm SIMD128 cases executed");
const csv = (name) => readFileSync(path.join(directory, name), "utf8").trim().split(",");
const selectedLanes = csv("lanes.txt");
const selection = { types: csv("types.txt"), families: csv("families.txt"),
  lanes: selectedLanes[0] === "all" ? [...Array.from({ length: 63 }, (_, i) => i + 2), "preferred"]
    : selectedLanes.map((value) => value === "preferred" ? value : Number(value)) };
if (rows.length !== selection.types.length * selection.families.length ||
    selection.types.some((element) => selection.families.some((family) =>
      rows.filter((row) => row.element === element && row.family === family).length !== 1))) {
  throw new Error("Wasm execution rows do not match the requested selection");
}
for (const row of rows) {
  row.executedInventory = verifyWasmInventory(row.execution, row.family, row.element, selection.lanes);
  verifyWasmInventory(row.scalarC, row.family, row.element, selection.lanes);
}
const counted = {
  execution: JSON.parse(readFileSync(path.join(directory, "counted/result.json"), "utf8")),
  scalarC: JSON.parse(readFileSync(path.join(directory, "counted/scalar-c/result.json"), "utf8")),
};
verifyCountedRuntime(counted.execution, counted.scalarC);
const report = { schemaVersion: 1, selection, counted,
  revision: readFileSync(path.join(directory, "revision.txt"), "utf8").trim(),
  compilerVersion: readFileSync(path.join(directory, "compiler.txt"), "utf8").trim(),
  runtime: process.version, requested_wasm_matrix_complete: true, rows,
  scope: "The explicitly selected SIMD corpus; native platform/tier coverage is reported separately." };
writeFileSync(path.join(directory, "summary.json"), JSON.stringify(report, null, 2) + "\n");
console.log(`Wasm SIMD128 and scalar-C matrix: ${rows.length} batches executed`);
