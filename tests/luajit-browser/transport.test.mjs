import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createGuest, createCompiler} from '../../runtime/luajit/host.mjs';
import {assetsFor, sha256, inflateSnapshot} from '../../runtime/luajit/assets.mjs';
import {gzipSync} from 'node:zlib';
class Worker {
  static instances = [];
  constructor() { Worker.instances.push(this); this.sent = []; }
  postMessage(message) { this.sent.push(message); }
  terminate() { this.terminated = true; }
  deliver(data) { this.onmessage({data}); }
}
globalThis.Worker = Worker;
const options = {manifestUrl: 'https://example.test/runtime/guest-manifest.json', app: new Uint8Array([1, 2, 3])};
test('busy cancellation settles the pending request and drops late responses', async () => {
  const abort = new AbortController();
  const starting = createCompiler({...options, signal: abort.signal});
  const worker = Worker.instances.at(-1);
  worker.deliver({type: 'compiler', sequence: 0, result: {ready: true}});
  const compiler = await starting;
  const request = compiler.request({kind: 'check', source: 'return 1'});
  assert.equal(worker.sent.at(-1).response.payloadField, 'source');
  assert.equal(new TextDecoder().decode(worker.sent.at(-1).payload), 'return 1');
  abort.abort(new Error('cancelled during execution'));
  await assert.rejects(request, /cancelled during execution/);
  assert.equal(worker.terminated, true);
  worker.deliver({type: 'compiler', sequence: 1, result: {ok: true, response: {}}});
  await assert.rejects(compiler.request({kind: 'check', source: 'return 2'}), /not waiting/);
});
test('host failure before receive keeps the actual initialization error', async () => {
  const guest = createGuest(options);
  Worker.instances.at(-1).deliver({type: 'failed', error: 'bad image', log: 'boot details'});
  await assert.rejects(guest.receive(), /bad image\nboot details/);
});
test('one retained session serializes requests and rejects overlapping callers', async () => {
  const starting = createCompiler(options);
  const worker = Worker.instances.at(-1);
  worker.deliver({type: 'compiler', sequence: 0, result: {ready: true}});
  const compiler = await starting;
  const request = compiler.request({kind: 'check', source: 'return 1'});
  await assert.rejects(compiler.request({kind: 'hover', offset: 1}), /already running/);
  worker.deliver({type: 'compiler', sequence: 1, result: {ok: true, response: {diagnostics: []}}});
  assert.deepEqual(await request, {diagnostics: []});
  compiler.close();
});
test('a missing guest response hits the host deadline', async () => {
  const guest = createGuest({...options, deadlineMs: 10});
  await assert.rejects(guest.receive(), /timed out/);
  assert.equal(Worker.instances.at(-1).terminated, true);
});
test('asset bytes and hashes are enforced before they reach the emulator', async () => {
  const original = globalThis.fetch;
  try {
    const bytes = new TextEncoder().encode('known guest input');
    const manifest = {assets: {'kernel': {bytes: bytes.length, sha256: await sha256(bytes)}}};
    globalThis.fetch = async () => new Response(bytes);
    assert.deepEqual(await assetsFor(manifest, options.manifestUrl)('kernel'), bytes);
    globalThis.fetch = async () => new Response(new Uint8Array(bytes.length));
    await assert.rejects(assetsFor(manifest, options.manifestUrl)('kernel'), /SHA-256/);
    globalThis.fetch = async () => new Response(new Uint8Array(bytes.length + 1));
    await assert.rejects(assetsFor(manifest, options.manifestUrl)('kernel'), /exceeds/);
    await assert.rejects(assetsFor(manifest, options.manifestUrl)('../kernel'), /Invalid guest asset/);
  } finally { globalThis.fetch = original; }
});

test('a restore failure retries normal boot once and ignores the discarded worker', async () => {
  const progress = [];
  const guest = createGuest({...options, onProgress: message => progress.push(message)});
  const first = Worker.instances.at(-1);
  const received = guest.receive();
  first.deliver({type: 'snapshot-selected'});
  first.deliver({type: 'failed', error: 'invalid saved state', log: ''});
  const replacement = Worker.instances.at(-1);
  assert.notEqual(first, replacement);
  assert.equal(first.terminated, true);
  assert.equal(replacement.sent[0].snapshot, false);
  assert.equal(progress[0].type, 'snapshot-fallback');
  first.deliver({type: 'done', sequence: 0, result: {stale: true}});
  replacement.deliver({type: 'done', sequence: 0, result: {ok: true}});
  assert.deepEqual((await received).result, {ok: true});
  guest.close();
});
test('snapshot decompression stops at the declared size and rejects corrupt data', async () => {
  const bytes = new Uint8Array(65536).fill(7), packed = gzipSync(bytes);
  assert.deepEqual(new Uint8Array(await inflateSnapshot(packed, bytes.length)), bytes);
  await assert.rejects(inflateSnapshot(packed, 1024), /exceeds/);
  await assert.rejects(inflateSnapshot(packed, bytes.length + 1), /mismatch/);
  await assert.rejects(inflateSnapshot(packed, 257 * 1024 * 1024), /Invalid/);
  await assert.rejects(inflateSnapshot(new Uint8Array([1, 2]), 2));
});

test('guest transfer leases check extents, permissions, releases and duplicate identities', async () => {
  const {createTransfers} = await import('../../runtime/luajit/transfers.mjs');
  const transfer = createTransfers([{id: 1, offset: 0, bytes: 2, writable: false},
    {id: 2, offset: 2, bytes: 3, writable: true}], new Uint8Array([1,2,0,0,0]).buffer);
  assert.deepEqual([...transfer.lease(1, 2).view], [1,2]);
  assert.throws(() => transfer.lease(1, 2, true), /access/);
  assert.throws(() => transfer.lease(2, 4, true), /extent/);
  transfer.lease(2, 3, true).view.set([5,6,7]);
  assert.throws(() => transfer.response(), /retained/);
  transfer.release(1); transfer.release(2);
  assert.throws(() => transfer.lease(1), /stale/);
  assert.deepEqual(transfer.response(), {leases:[{id:1},{id:2,offset:0,bytes:3}], payload:new Uint8Array([5,6,7])});
  assert.throws(() => createTransfers([{id:1,offset:0,bytes:0,writable:false},{id:1,offset:0,bytes:0,writable:false}]), /descriptor/);
  assert.throws(() => createTransfers([{id:1,offset:1,bytes:0,writable:false}]), /descriptor/);
  assert.throws(() => createTransfers([], new ArrayBuffer(1)), /Unclaimed/);
});
test('managed application framing preserves binary initialization and source bytes', async () => {
  const {applicationPayload} = await import('../../runtime/luajit/app-runtime.mjs');
  const packed = applicationPayload(new Uint8Array([9,0,8]), new Uint8Array([1,0,2]));
  assert.equal(new TextDecoder().decode(packed.subarray(0,8)), 'NUAPP001');
  assert.equal(new DataView(packed.buffer).getUint32(8,true), 3);
  assert.deepEqual([...packed.subarray(12)], [1,0,2,9,0,8]);
  assert.throws(() => applicationPayload(new Uint8Array(7*1024*1024)), /exceeds/);
});

test('compressed assets verify both encodings and enforce decoded extent', async () => {
  const {gzipSync} = await import('node:zlib');
  const original = globalThis.fetch;
  try {
    const bytes = new TextEncoder().encode('known guest input'), packed = gzipSync(bytes);
    const manifest = {delivery:{kernel:'kernel.gz'},assets:{
      kernel:{bytes:bytes.length,sha256:await sha256(bytes)},
      'kernel.gz':{bytes:packed.length,sha256:await sha256(packed)}}};
    globalThis.fetch=async url=>{assert.equal(new URL(url).pathname,'/runtime/kernel.gz');return new Response(packed);};
    assert.deepEqual(await assetsFor(manifest,options.manifestUrl)('kernel'),bytes);
    manifest.assets.kernel.bytes--;
    await assert.rejects(assetsFor(manifest,options.manifestUrl)('kernel'),/extent|exceeds/);
  } finally {globalThis.fetch=original;}
});
