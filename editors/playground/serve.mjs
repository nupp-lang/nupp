#!/usr/bin/env node
// A tiny static file server for dist/ — just enough to develop against,
// with correct MIME types for the module worker and the .lua asset.
import http from "node:http";
import { createReadStream, existsSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "dist");
const port = Number(process.env.PORT || 8787);

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".lua": "text/plain; charset=utf-8",
  ".svg": "image/svg+xml",
  ".map": "application/json",
  ".md": "text/markdown; charset=utf-8",
};

http
  .createServer((req, res) => {
    const url = new URL(req.url, "http://localhost");
    let file = path.join(root, decodeURIComponent(url.pathname));
    if (url.pathname === "/") file = path.join(root, "index.html");
    if (!file.startsWith(root)) {
      res.writeHead(403).end("forbidden");
      return;
    }
    if (!existsSync(file) || statSync(file).isDirectory()) {
      res.writeHead(404).end("not found");
      return;
    }
    res.writeHead(200, { "content-type": TYPES[path.extname(file)] || "application/octet-stream" });
    createReadStream(file).pipe(res);
  })
  .listen(port, () => console.log(`serving dist/ on http://localhost:${port}`));
