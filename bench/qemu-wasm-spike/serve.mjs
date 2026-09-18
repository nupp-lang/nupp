import http from 'node:http';
import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import path from 'node:path';

const root = path.resolve(process.argv[2] || 'build/qemu-wasm-spike/web');
const port = Number(process.argv[3] || 8097);
const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json', '.wasm': 'application/wasm' };
http.createServer(async (req, res) => {
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cache-Control', 'no-store');
  try {
    const url = new URL(req.url, 'http://localhost');
    if (url.pathname === '/echo') {
      const chunks = []; let bytes = 0;
      for await (const chunk of req) {
        bytes += chunk.length;
        if (bytes > 16 * 1024 * 1024) { res.writeHead(413); res.end(); return; }
        chunks.push(chunk);
      }
      res.setHeader('Content-Type', 'application/octet-stream');
      res.end(Buffer.concat(chunks)); return;
    }
    if (url.pathname === '/bytes') { res.end(Buffer.alloc(4096, 42)); return; }
    if (url.pathname === '/slow') { setTimeout(() => res.end('delayed'), 200); return; }
    const name = decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname);
    const file = path.resolve(root, '.' + name);
    if (!file.startsWith(root + path.sep)) throw new Error('invalid path');
    const info = await stat(file);
    if (!info.isFile()) throw new Error('not a file');
    res.setHeader('Content-Type', types[path.extname(file)] || 'application/octet-stream');
    res.setHeader('Content-Length', info.size);
    createReadStream(file).on('error', () => res.destroy()).pipe(res);
  } catch {
    res.writeHead(404);
    res.end('Not found');
  }
}).listen(port, '127.0.0.1', () => console.log(`http://127.0.0.1:${port}`));
