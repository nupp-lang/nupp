#!/usr/bin/env node
import http from "node:http";
import { createReadStream, existsSync, statSync } from "node:fs";
import path from "node:path";

const root = path.resolve(process.argv[2] || "dist/browser");
const port = Number(process.env.PORT || 8787);
const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json",
  ".lua": "text/plain; charset=utf-8",
  ".wasm": "application/wasm",
};

http.createServer((request, response) => {
  const address = new URL(request.url, "http://localhost");
  let file = path.resolve(root, "." + decodeURIComponent(address.pathname));
  if (address.pathname === "/") file = path.join(root, "index.html");
  if (file !== root && !file.startsWith(root + path.sep)) {
    response.writeHead(403).end("forbidden");
    return;
  }
  if (!existsSync(file) || statSync(file).isDirectory()) {
    response.writeHead(404).end("not found");
    return;
  }
  response.writeHead(200, {
    "content-type": types[path.extname(file)] || "application/octet-stream",
  });
  createReadStream(file).pipe(response);
}).listen(port, "127.0.0.1", () => {
  console.log("serving " + root + " on http://127.0.0.1:" + port);
});
