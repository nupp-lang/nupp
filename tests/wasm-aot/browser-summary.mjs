import { readFileSync } from "node:fs";

const cases = process.argv.slice(2).map((file) => JSON.parse(readFileSync(file, "utf8")));
if (cases.length !== 12 || cases.some((entry) => !entry.ok)) {
  throw new Error(
    "plain, scalar, SIMD, HTTP, browser-platform, derives, cancellation, runtime-error, "
    + "missing-artifact, and the three worker-task results are required",
  );
}
process.stdout.write(JSON.stringify({ok: true, cases}, null, 2) + "\n");
