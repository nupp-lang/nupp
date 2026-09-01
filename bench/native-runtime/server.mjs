import { createServer } from "node:http";
import { createServer as createTcpServer } from "node:net";
import { once } from "node:events";
import { setTimeout as delay } from "node:timers/promises";

const small = Buffer.alloc(64, 0x61);
const large = Buffer.alloc(4 * 1024 * 1024, 0x62);
const slowChunk = Buffer.alloc(64 * 1024, 0x63);
const slowBytes = 256 * 1024 * 1024;
const slowWriterChunk = Buffer.alloc(1024, 0x64);
const slowWriterBytes = 8 * 1024 * 1024;
const netSlowWriterChunk = Buffer.alloc(1024, 0x65);

async function sendSlow(res) {
  res.writeHead(200, {
    "Content-Length": slowBytes,
    "Content-Type": "application/octet-stream",
  });
  try {
    for (let sent = 0; sent < slowBytes; sent += slowChunk.length) {
      if (!res.write(slowChunk)) {
        await once(res, "drain");
      }
    }
    res.end();
  } catch {
    res.destroy();
  }
}

async function sendSlowWriter(res) {
  res.writeHead(200, {
    "Content-Length": slowWriterBytes,
    "Content-Type": "application/octet-stream",
  });
  try {
    for (let sent = 0; sent < slowWriterBytes; sent += slowWriterChunk.length) {
      await delay(10);
      if (!res.write(slowWriterChunk)) {
        await once(res, "drain");
      }
    }
    res.end();
  } catch {
    res.destroy();
  }
}

const server = createServer((req, res) => {
  if (req.method !== "GET") {
    res.writeHead(405, { "Content-Length": 0 });
    res.end();
    return;
  }
  if (req.url === "/small") {
    res.writeHead(200, { "Content-Length": small.length });
    res.end(small);
    return;
  }
  if (req.url === "/large") {
    res.writeHead(200, { "Content-Length": large.length });
    res.end(large);
    return;
  }
  if (req.url === "/slow-reader") {
    void sendSlow(res);
    return;
  }
  if (req.url === "/slow-writer") {
    void sendSlowWriter(res);
    return;
  }
  res.writeHead(404, { "Content-Length": 0 });
  res.end();
});

server.on("clientError", (_error, socket) => socket.destroy());
let httpPort;
let tcpPort;
let ready = false;
function reportReady() {
  if (!ready && httpPort !== undefined && tcpPort !== undefined) {
    ready = true;
    process.stdout.write(`READY ${httpPort} ${tcpPort}\n`);
  }
}

function listenFailed(kind, error) {
  console.error(`native runtime peer: ${kind} listen failed: ${error.stack ?? error}`);
  if (server.listening) server.close();
  if (tcpServer.listening) tcpServer.close();
  process.exitCode = 1;
}

server.once("error", (error) => listenFailed("HTTP", error));
server.listen(0, "127.0.0.1", () => {
  const address = server.address();
  httpPort = address.port;
  reportReady();
});

const tcpServer = createTcpServer((socket) => {
  socket.on("error", () => socket.destroy());
  void (async () => {
    try {
      while (!socket.destroyed) {
        await delay(100);
        if (!socket.write(netSlowWriterChunk)) {
          await once(socket, "drain");
        }
      }
    } catch {
      socket.destroy();
    }
  })();
});

tcpServer.once("error", (error) => listenFailed("TCP", error));
tcpServer.listen(0, "127.0.0.1", () => {
  const address = tcpServer.address();
  tcpPort = address.port;
  reportReady();
});
