import { writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { once } from "node:events";

const portFile = process.argv[2];
if (!portFile) {
  console.error("usage: node server.mjs PORT_FILE");
  process.exit(2);
}

const small = Buffer.alloc(64, 0x61);
const large = Buffer.alloc(4 * 1024 * 1024, 0x62);
const slowChunk = Buffer.alloc(64 * 1024, 0x63);
const slowBytes = 256 * 1024 * 1024;

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
  res.writeHead(404, { "Content-Length": 0 });
  res.end();
});

server.on("clientError", (_error, socket) => socket.destroy());
server.listen(0, "127.0.0.1", () => {
  const address = server.address();
  writeFileSync(portFile, String(address.port), "ascii");
});

