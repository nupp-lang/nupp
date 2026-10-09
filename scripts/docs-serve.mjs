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

// Runs one build step. A required step that fails ends the run; an optional
// one reports the failure and answers false, so the server can come up
// without what it would have produced.
function run(label, cmd, args, { optional = false, ...opts } = {}) {
  console.log(`\n> ${label}: ${cmd} ${args.join(" ")}`);
  const result = spawnSync(cmd, args, { stdio: "inherit", cwd: root, ...opts });
  const failure = result.error
    ? `${label} failed to start: ${result.error.message}`
    : result.status !== 0
      ? `${label} exited with status ${result.status}`
      : null;
  if (failure === null) return true;
  console.error(failure);
  if (!optional) process.exit(result.status || 1);
  return false;
}

// The playground needs the browser guest, which only builds on Linux and is
// otherwise a CI artifact, so on a laptop its build fails more often than
// not. The docs are what a reader of this server usually wants, and they do
// not depend on it: a failed playground build is reported, and the docs are
// served without the playground route.
let playgroundAvailable = true;
if (!skipBuild) {
  run("docs build", path.join(root, "bin/nupp"), ["doc", "--kind", "site"]);
  // The playground's own `npm run build` also serves; `node build.mjs`
  // alone just builds dist/, which is all that's wanted here.
  playgroundAvailable = run("playground build", "node", ["build.mjs"], { cwd: playgroundDir, optional: true });
  if (!playgroundAvailable) {
    console.error("\nthe playground did not build; serving the docs without it");
  }
} else {
  console.log("--no-build: serving whatever is already in build/docs and editors/playground/dist");
}

if (!existsSync(docsDir)) {
  console.error("\nbuild/docs does not exist; remove --no-build, or build it first.");
  process.exit(1);
}
if (!existsSync(playgroundDist)) {
  playgroundAvailable = false;
  console.error("\neditors/playground/dist does not exist; serving the docs without the playground");
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
    if (!playgroundAvailable) {
      res.writeHead(503, { "content-type": "text/plain; charset=utf-8" });
      res.end("the playground is not built on this machine; see editors/playground/README.md");
      return;
    }
    serveFrom(playgroundDist, url.pathname.slice(PLAYGROUND_PREFIX.length), res);
    return;
  }
  serveFrom(docsDir, url.pathname.slice(1), res);
});

server.listen(port, () => {
  console.log(`\ndocs:       http://localhost:${port}/`);
  if (playgroundAvailable) {
    console.log(`playground: http://localhost:${port}${PLAYGROUND_PREFIX}/`);
  } else {
    console.log("playground: not built; its route answers 503");
  }
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
