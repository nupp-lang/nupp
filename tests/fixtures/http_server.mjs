// Loopback HTTP/1.1 server used by the native HTTP provider tests.

import { writeFileSync } from "node:fs";
import { createServer } from "node:http";

const portFile = process.argv[2];
if (!portFile) {
  console.error("usage: node http_server.mjs PORT_FILE");
  process.exit(2);
}

const largeBody = Buffer.from("0123456789abcdef".repeat(4 * 1024 * 1024 / 16));
let loopHits = 0;

function send(res, status, body = Buffer.alloc(0), headers = {}) {
  res.writeHead(status, {
    "Content-Length": body.length,
    ...headers,
  });
  res.end(body);
}

const server = createServer((req, res) => {
  if (req.method === "GET") {
    if (req.url === "/redirect") {
      const { port } = server.address();
      send(res, 302, undefined, {
        Location: `http://localhost:${port}/authorization`,
      });
      return;
    }
    if (req.url === "/redirect-cookie") {
      const { port } = server.address();
      send(res, 302, undefined, {
        Location: `http://localhost:${port}/cookie`,
      });
      return;
    }
    if (req.url === "/loop") {
      loopHits += 1;
      send(res, 302, undefined, { Location: "/loop" });
      return;
    }
    if (req.url === "/loop-count") {
      // How many times /loop was asked for since the last read, so a test can
      // tell one request per hop from a transport quietly chaining hops.
      const body = Buffer.from(String(loopHits), "ascii");
      loopHits = 0;
      send(res, 200, body);
      return;
    }
    if (req.url === "/slow") {
      // Not answered within a test's patience: what a caller cancels against.
      const timer = setTimeout(
        () => send(res, 200, Buffer.from("slow response\n")), 30000);
      res.on("close", () => clearTimeout(timer));
      return;
    }

    let body;
    if (req.url === "/authorization") {
      body = Buffer.from(req.headers.authorization ?? "none", "ascii");
    } else if (req.url === "/cookie") {
      body = Buffer.from(req.headers.cookie ?? "none", "ascii");
    } else if (req.url === "/large") {
      body = largeBody;
    } else {
      body = Buffer.from("small response\n");
    }
    send(res, 200, body, {
      "Content-Type": "application/octet-stream",
      "X-Repeated": ["one", "two"],
    });
    return;
  }

  if (req.method === "POST" && req.url === "/early") {
    // Answer before consuming the upload. Draining the readable side after ending
    // the response lets the socket close with FIN instead of resetting and losing
    // the response bytes the client already parsed.
    req.on("error", () => {});
    req.resume();
    send(res, 413, undefined, { Connection: "close" });
    return;
  }

  if (req.method === "POST") {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => send(res, 200, Buffer.concat(chunks)));
    return;
  }

  send(res, 405);
});

server.on("clientError", (_error, socket) => socket.destroy());
server.listen(0, "127.0.0.1", () => {
  const { port } = server.address();
  writeFileSync(portFile, String(port), "ascii");
});
