import { readFileSync } from "node:fs";

const cases = process.argv.slice(2).map((file) => JSON.parse(readFileSync(file, "utf8")));
if (cases.length !== 5 || cases.some((entry) => !entry.ok)) {
  throw new Error("plain, scalar, SIMD, runtime-error, and missing-artifact results are required");
}
process.stdout.write(JSON.stringify({ok: true, cases}, null, 2) + "\n");
