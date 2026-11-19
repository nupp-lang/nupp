// Loopback HTTP/1.1 server used by the native HTTP provider tests.

import { readFileSync, writeFileSync } from "node:fs";
import { createServer as createHttp } from "node:http";
import { createServer as createHttps } from "node:https";
import { createServer as createTcp } from "node:net";
import { gzipSync } from "node:zlib";

const portFile = process.argv[2];
if (!portFile) {
  console.error("usage: node http_server.mjs PORT_FILE");
  process.exit(2);
}

const largeBody = Buffer.from("0123456789abcdef".repeat(4 * 1024 * 1024 / 16));
let loopHits = 0;
let wireCase = 0;
const wireResults = new Map();
const firstFrame = "2000\r\n" + "x".repeat(8192) + "\r\n";

function send(res, status, body = Buffer.alloc(0), headers = {}) {
  res.writeHead(status, {
    "Content-Length": body.length,
    ...headers,
  });
  res.end(body);
}

function startWireUpload(res) {
  const id = String(++wireCase);
  const listener = createTcp((socket) => {
    listener.close();
    let wire = "";
    let bodyStart = -1;
    let answered = false;
    socket.on("error", () => {});
    socket.on("data", (chunk) => {
      wire += chunk.toString("latin1");
      if (wire.length > 32768) {
        socket.destroy();
        return;
      }
      if (bodyStart < 0) {
        const end = wire.indexOf("\r\n\r\n");
        if (end < 0) return;
        bodyStart = end + 4;
      }
      // Only a complete first payload can trigger the early response.
      if (!answered && wire.startsWith(firstFrame, bodyStart)) {
        answered = true;
        socket.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok");
      }
    });
    wireResults.set(id, new Promise((resolve) => {
      socket.on("close", () => {
        const head = wire.slice(0, bodyStart);
        const body = wire.slice(bodyStart);
        if (!answered || !head.startsWith("POST /upload HTTP/1.1\r\n") ||
            !/\r\ntransfer-encoding: chunked\r\n/i.test(head) || /\r\ncontent-length:/i.test(head)) {
          resolve("expected unknown-length chunked payload and early response");
        } else if (body === firstFrame) {
          resolve("open");
        } else if (body.endsWith("0\r\n\r\n")) {
          resolve("final zero chunk");
        } else {
          resolve("unexpected upload bytes: " + (body.length - firstFrame.length));
        }
      });
    }));
  });
  listener.listen(0, "127.0.0.1", () => {
    send(res, 200, Buffer.from(listener.address().port + "/" + id));
  });
}

function respond(req, res) {
  if (req.method === "GET") {
    if (req.url === "/early-wire") {
      startWireUpload(res);
      return;
    }
    if (req.url.startsWith("/early-wire-result/")) {
      const id = req.url.slice("/early-wire-result/".length);
      const result = wireResults.get(id);
      if (result === undefined) {
        send(res, 404);
      } else {
        wireResults.delete(id);
        void result.then((body) => send(res, 200, Buffer.from(body)));
      }
      return;
    }
    if (req.url === "http://origin.invalid/proxy") {
      send(res, 200, Buffer.from(req.headers["proxy-authorization"] ?? "none"));
      return;
    }
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
    if (req.url.startsWith("/redirect-host")) {
      const { port } = server.address();
      send(res, 302, undefined, {
        Location: `http://localhost:${port}/host?token=secret`,
      });
      return;
    }
    if (req.url.startsWith("/host")) {
      // What a cross-origin hop arrived with: its own Host, and no Referer
      // carrying the previous URL's query.
      const body = Buffer.from(
        `${req.headers.host ?? "none"} ${req.headers.referer ?? "none"}`, "ascii");
      send(res, 200, body);
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
    if (req.url === "/slow-body") {
      // Commit the response head, then leave its body pending. This separates
      // cancellation while reading a body from cancellation while waiting for
      // a response at all.
      res.writeHead(200, {
        "Content-Length": 14,
        "Content-Type": "application/octet-stream",
      });
      res.flushHeaders();
      const timer = setTimeout(() => res.end("late response\n"), 30000);
      res.on("close", () => clearTimeout(timer));
      return;
    }

    if (req.url === "/gzip") {
      send(res, 200, gzipSync(Buffer.from("gzip\0response\n")), {
        "Content-Encoding": "gzip",
      });
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
      ...(req.url === "/large" && typeof req.headers["x-asked"] === "string"
        ? { "X-Asked-Seen": req.headers["x-asked"] }
        : {}),
    });
    return;
  }

  if (req.method === "POST" && req.url === "/early") {
    // Answer before consuming the upload, and never consume it. Leaving the
    // readable side paused is what makes this deterministic: the client's
    // remaining body has nowhere to go once the kernel buffers fill, so it
    // cannot outrun the response however the two are scheduled.
    //
    // The connection is deliberately left open. Ending it here would close a
    // socket still holding unread request bytes, which resets rather than
    // finishing and discards the response the client had already been sent.
    // Draining first only narrowed that window; the client owns the close.
    req.on("error", () => {});
    req.pause();
    send(res, 413);
    return;
  }

  if (req.method === "POST" && req.url === "/slow-upload") {
    // Deliberately do not consume the request. A streaming client eventually
    // reaches transport backpressure, leaving cancellation responsible for
    // closing both its reader loop and native transfer.
    const timer = setTimeout(() => send(res, 200), 30000);
    res.on("close", () => clearTimeout(timer));
    return;
  }

  if (req.method === "POST" && req.url === "/redirect-upload") {
    req.on("end", () => send(res, 307, undefined, { Location: "/echo" }));
    req.resume();
    return;
  }

  if (req.method === "POST") {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => send(res, 200, Buffer.concat(chunks)));
    return;
  }

  send(res, 405);
}

const server = process.argv[3]
  ? createHttps({
      cert: readFileSync(process.argv[3]),
      key: readFileSync(process.argv[4]),
    }, respond)
  : createHttp(respond);

server.on("clientError", (_error, socket) => socket.destroy());
server.listen(0, "127.0.0.1", () => {
  const { port } = server.address();
  writeFileSync(portFile, String(port), "ascii");
});
