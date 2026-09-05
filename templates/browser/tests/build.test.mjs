import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";

const bundle = await readFile("dist/app.lua", "utf8");
assert.match(bundle, /nupp\.runtime\.backend\.browser/);
assert.match(bundle, /nupp\.runtime\.browser\.crypto/);
assert.match(bundle, /nupp\.runtime\.browser\.storage/);
for (const file of ["scripts/serve.mjs", "web/app.mjs"]) {
  assert.equal(spawnSync(process.execPath, ["--check", file]).status, 0, file);
}
assert.equal(spawnSync("sh", ["-n", "scripts/package.sh"]).status, 0);
console.log("ok");
