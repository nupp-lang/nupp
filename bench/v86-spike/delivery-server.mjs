// Deterministic localhost link model: optional aggregate payload rate and
// per-request first-byte delay. Reports HTTP bodies, excluding protocol headers.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import {brotliCompressSync, constants} from 'node:zlib';

const root = path.resolve('build/v86-spike');
const rate = Number(process.env.DELIVERY_RATE || 0);
const delay = Number(process.env.DELIVERY_DELAY_MS || 0);
const quality = Number(process.env.DELIVERY_BROTLI_QUALITY || 9);
const port = Number(process.argv[2] || 8103);
const files = JSON.parse(fs.readFileSync('bench/v86-spike/results/assets.json')).gameFiles;
const assets = new Map();
if (process.env.STARTUP_PROBE === '1') {
  for (const variant of (process.env.DELIVERY_VARIANTS || 'serial,parallel,parallel-raw,snapshot,snapshot-bundled').split(',')) {
    const names = files.filter(name => !variant.startsWith('snapshot') || !['initramfs.gz', 'assets/bzimage.bin', 'assets/seabios.bin', 'assets/vgabios.bin'].includes(name));
    if (variant === 'parallel-raw') names.splice(names.indexOf('initramfs.gz'), 1, 'initramfs.cpio');
    if (variant.startsWith('snapshot')) names.push('guest-state.bin');
    if (variant === 'snapshot-bundled') names.splice(names.indexOf('assets/libv86.mjs'), 1);
    names.push('native-modules.lua', 'services.lua', 'worker.ljbc', 'worker-lane.mjs', 'check-startup.html', 'check-startup.mjs');
    for (const name of names) {
      const filename = path.join(root, 'startup', variant, name);
      if (!fs.existsSync(filename)) continue;
      const original = fs.readFileSync(filename);
      const br = brotliCompressSync(original, {params: {[constants.BROTLI_PARAM_QUALITY]: quality}});
      assets.set('/' + variant + '/' + name, {original, br});
      if (name === 'guest-state.bin' || name === 'initramfs.cpio') console.log(JSON.stringify({variant, name, rawBytes: original.length, brotliBytes: br.length}));
    }
  }
} else {
  for (const name of files) {
    let bytes = fs.readFileSync(path.join(root, 'memory-64-runtime/web', name));
    if (name === 'vm-worker.mjs') bytes = Buffer.from(bytes.toString()
      .replace('earlyprintk=serial,ttyS0,115200', 'quiet').replace('traceMessages = true;', 'traceMessages = false;'));
    for (const variant of ['raw', 'compressed', 'slim']) {
      const original = variant === 'slim' && name === 'assets/bzimage.bin'
        ? fs.readFileSync(path.join(root, 'performance/kernel-empty-rootfs.bin')) : bytes;
      const br = brotliCompressSync(original, {params: {[constants.BROTLI_PARAM_QUALITY]: quality}});
      assets.set('/' + variant + '/' + name, {original, br});
    }
  }
}
const types = {'.html': 'text/html', '.mjs': 'text/javascript', '.wasm': 'application/wasm'};
let requests = [];
const queue = [];
setInterval(() => {
  let budget = rate / 50;
  while (budget > 0 && queue.length) {
    const entry = queue.shift();
    if (entry.res.destroyed) continue;
    const size = Math.min(16384, Math.floor(budget), entry.body.length - entry.offset);
    if (!size) break;
    entry.res.write(entry.body.subarray(entry.offset, entry.offset + size));
    entry.offset += size; budget -= size;
    if (entry.offset === entry.body.length) entry.res.end(); else queue.push(entry);
  }
}, 20).unref();
http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname === '/_stats') {
    if (req.method === 'POST') requests = [];
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({rateBytesPerSecond: rate, firstByteDelayMs: delay, brotliQuality: quality, requests,
      payloadBytes: requests.reduce((sum, entry) => sum + entry.bytes, 0)})); return;
  }
  const asset = assets.get(url.pathname);
  if (!asset) { res.writeHead(404); res.end('Not found'); return; }
  const compressed = !url.pathname.startsWith('/raw/') && /\bbr\b/.test(req.headers['accept-encoding'] || '') && asset.br.length < asset.original.length;
  const body = compressed ? asset.br : asset.original;
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cache-Control', url.pathname.startsWith('/raw/') ? 'no-store' : 'public, max-age=31536000, immutable');
  res.setHeader('Vary', 'Accept-Encoding');
  res.setHeader('Content-Type', types[path.extname(url.pathname)] || 'application/octet-stream');
  if (compressed) res.setHeader('Content-Encoding', 'br');
  res.setHeader('Content-Length', body.length);
  const startedAt = performance.now();
  res.on('finish', () => requests.push({path: url.pathname, bytes: body.length, encoding: compressed ? 'br' : 'identity', startedAt, finishedAt: performance.now()}));
  setTimeout(() => {
    if (res.destroyed) return;
    if (rate) queue.push({res, body, offset: 0}); else res.end(body);
  }, delay);
}).listen(port, '127.0.0.1', () => console.log(JSON.stringify({port, rate, delay})));
