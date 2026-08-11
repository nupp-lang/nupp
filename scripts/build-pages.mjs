#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import {
  cpSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const docs = path.join(root, "build/docs");
const playground = path.join(root, "editors/playground/dist");
const output = path.join(root, "build/pages");

function run(command, args, cwd = root) {
  execFileSync(command, args, { cwd, stdio: "inherit" });
}

function htmlFiles(directory) {
  return readdirSync(directory, { recursive: true, withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith(".html"))
    .map((entry) => path.join(entry.parentPath, entry.name));
}

run(path.join(root, "bin/nupp"), ["doc", "site"]);
run(process.execPath, ["build.mjs"], path.join(root, "editors/playground"));

rmSync(output, { force: true, recursive: true });
mkdirSync(path.join(output, "playground"), { recursive: true });
cpSync(docs, output, { recursive: true });
cpSync(playground, path.join(output, "playground"), { recursive: true });
writeFileSync(path.join(output, ".nojekyll"), "");

const socialMetadata = [
  '<meta property="og:type" content="website">',
  '<meta property="og:site_name" content="Nupp">',
  '<meta property="og:image" content="https://nupp-lang.org/images/og.png">',
  '<meta property="og:image:width" content="1731">',
  '<meta property="og:image:height" content="909">',
  '<meta property="og:image:alt" content="Nupp — LuaJIT with static guarantees.">',
  '<meta name="twitter:card" content="summary_large_image">',
  '<meta name="twitter:image" content="https://nupp-lang.org/images/og.png">',
].join("");

for (const file of htmlFiles(output)) {
  const html = readFileSync(file, "utf8");
  writeFileSync(file, html.replace("</head>", `${socialMetadata}</head>`));
}

console.log(`Built ${path.relative(root, output)}`);
