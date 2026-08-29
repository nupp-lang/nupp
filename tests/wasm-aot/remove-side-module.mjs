import { readFileSync, rmSync } from "node:fs";
import path from "node:path";

const root = path.resolve(process.argv[2]);
const manifest = JSON.parse(readFileSync(path.join(root, "nupp-browser-app.json"), "utf8"));
if (manifest.sideModules.length !== 1) {
  throw new Error("the missing-artifact fixture requires one side module");
}
const file = path.resolve(root, manifest.sideModules[0].file);
if (!file.startsWith(root + path.sep)) throw new Error("side module escaped the fixture");
rmSync(file);
