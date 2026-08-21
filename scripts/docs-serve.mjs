#!/usr/bin/env node
// Builds the docs site and the playground, then serves both from one
// server: the docs site at /, the playground at /playground/ — the same
// path the home page's hero links to, so that link actually
// resolves here instead of 404ing (see editors/playground/README.md and
// the commit that added the button).
//
// Run as `nupp task docs-serve` (nupp.lua's tasks.docs-serve names this
// script); invoking it directly works the same, just without nupp's own
// argument handling in front of it.
//
// Usage: node scripts/docs-serve.mjs [--no-build]
//   PORT=8000 node scripts/docs-serve.mjs
//   nupp task docs-serve --no-build
import { spawnSync } from "node:child_process";
import http from "node:http";
import { createReadStream, existsSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const docsDir = path.join(root, "build/docs");
const playgroundDir = path.join(root, "editors/playground");
const playgroundDist = path.join(playgroundDir, "dist");
const port = Number(process.env.PORT || 8000);
const skipBuild = process.argv.includes("--no-build");

function run(label, cmd, args, opts = {}) {
  console.log(`\n> ${label}: ${cmd} ${args.join(" ")}`);
  const result = spawnSync(cmd, args, { stdio: "inherit", cwd: root, ...opts });
  if (result.error) {
    console.error(`${label} failed to start: ${result.error.message}`);
    process.exit(1);
  }
  if (result.status !== 0) {
    console.error(`${label} exited with status ${result.status}`);
    process.exit(result.status ?? 1);
  }
}

if (!skipBuild) {
  run("docs build", path.join(root, "bin/nupp"), ["doc", "site"]);
  // The playground's own `npm run build` also serves; `node build.mjs`
  // alone just builds dist/, which is all that's wanted here.
  run("playground build", "node", ["build.mjs"], { cwd: playgroundDir });
} else {
  console.log("--no-build: serving whatever is already in build/docs and editors/playground/dist");
}

for (const [label, dir] of [["build/docs", docsDir], ["editors/playground/dist", playgroundDist]]) {
  if (!existsSync(dir)) {
    console.error(`\n${label} does not exist — remove --no-build, or build it first.`);
    process.exit(1);
  }
}

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".lua": "text/plain; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".ico": "image/x-icon",
  ".json": "application/json",
  ".map": "application/json",
  ".md": "text/markdown; charset=utf-8",
  ".txt": "text/plain; charset=utf-8",
};

function serveFrom(base, urlPath, res) {
  let file = path.join(base, decodeURIComponent(urlPath));
  if (urlPath === "" || urlPath.endsWith("/")) file = path.join(file, "index.html");
  if (!file.startsWith(base)) {
    res.writeHead(403).end("forbidden");
    return;
  }
  if (!existsSync(file) || statSync(file).isDirectory()) {
    res.writeHead(404).end("not found");
    return;
  }
  res.writeHead(200, { "content-type": TYPES[path.extname(file)] || "application/octet-stream" });
  createReadStream(file).pipe(res);
}

const PLAYGROUND_PREFIX = "/playground";

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");
  if (url.pathname === PLAYGROUND_PREFIX || url.pathname.startsWith(PLAYGROUND_PREFIX + "/")) {
    serveFrom(playgroundDist, url.pathname.slice(PLAYGROUND_PREFIX.length), res);
    return;
  }
  serveFrom(docsDir, url.pathname.slice(1), res);
});

server.listen(port, () => {
  console.log(`\ndocs:       http://localhost:${port}/`);
  console.log(`playground: http://localhost:${port}${PLAYGROUND_PREFIX}/`);
  console.log("\nCtrl+C to stop.");
});

let shuttingDown = false;
function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`\nReceived ${signal}, shutting down…`);
  server.close(() => process.exit(0));
  // server.close() waits for in-flight requests; don't hang forever on one
  // that never finishes.
  setTimeout(() => process.exit(0), 2000).unref();
}
process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));
