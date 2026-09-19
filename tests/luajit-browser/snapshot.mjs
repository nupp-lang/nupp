import {createGuest} from './host.mjs';
const output = document.querySelector('#result');
const terminal = document.querySelector('#terminal');
const profile = new URL(location.href).searchParams.get('profile') || 'runner';
const guest = createGuest({manifestUrl: './guest-manifest.json', profile,
  app: new TextEncoder().encode('return true'), captureSnapshot: true, deadlineMs: 180000,
  onProgress: message => { if (message.log) terminal.textContent = message.log; }});
try {
  const result = await guest.receive();
  if (result.type !== 'snapshot') throw new Error('Guest did not stop at the snapshot gate');
  const compressed = new Uint8Array(await new Response(new Blob([result.state]).stream().pipeThrough(new CompressionStream('gzip'))).arrayBuffer());
  let binary = '';
  for (let offset = 0; offset < compressed.length; offset += 8192) binary += String.fromCharCode(...compressed.subarray(offset, offset + 8192));
  output.textContent = JSON.stringify({ok: true, profile, buildKey: result.buildKey,
    memoryMiB: result.memoryMiB, uncompressedBytes: result.state.byteLength,
    compressedBytes: compressed.length, resources: {snapshotBase64: btoa(binary)}});
  output.dataset.status = 'passed';
} catch (error) {
  output.textContent = JSON.stringify({ok: false, error: String(error.stack || error)});
  output.dataset.status = 'failed';
} finally { guest.close(); }
