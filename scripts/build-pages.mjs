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
function run(command, args, cwd = root) {
  execFileSync(command, args, { cwd, stdio: "inherit" });
}

function htmlFiles(directory) {
  return readdirSync(directory, { recursive: true, withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith(".html"))
    .map((entry) => path.join(entry.parentPath, entry.name));
}

const socialMetadata = [
  '<meta property="og:type" content="website">',
  '<meta property="og:site_name" content="Nupp">',
  '<meta property="og:image" content="https://nupp.org/images/og.png">',
  '<meta property="og:image:width" content="1731">',
  '<meta property="og:image:height" content="909">',
  '<meta property="og:image:alt" content="Nupp — LuaJIT with static guarantees.">',
  '<meta name="twitter:card" content="summary_large_image">',
  '<meta name="twitter:image" content="https://nupp.org/images/og.png">',
].join("");

function addSocialMetadata(files) {
  for (const file of files) {
    const html = readFileSync(file, "utf8");
    writeFileSync(file, html.replace("</head>", `${socialMetadata}</head>`));
  }
}

export function assemblePages({ docs, output }) {
  rmSync(output, { force: true, recursive: true });
  mkdirSync(output, { recursive: true });
  cpSync(docs, output, { recursive: true });
  addSocialMetadata(htmlFiles(output));
  writeFileSync(path.join(output, ".nojekyll"), "");
  writeFileSync(path.join(output, "CNAME"), "nupp.org\n");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  run(path.join(root, "bin/nupp"), ["doc", "--kind", "site"]);
  const output = path.join(root, "build/pages");
  assemblePages({ docs: path.join(root, "build/docs"), output });
  console.log(`Built ${path.relative(root, output)}`);
}
