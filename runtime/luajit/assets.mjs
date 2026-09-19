const MAX_ASSET_BYTES = 256 * 1024 * 1024;
export async function inflateSnapshot(packed, expectedBytes) {
  if (!Number.isSafeInteger(expectedBytes) || expectedBytes <= 0 || expectedBytes > MAX_ASSET_BYTES)
    throw new Error('Invalid snapshot extent');
  const reader = new Blob([packed]).stream().pipeThrough(new DecompressionStream('gzip')).getReader();
  const chunks = [];
  let length = 0;
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      length += value.length;
      if (length > expectedBytes) throw new Error('Snapshot exceeds its declared extent');
      chunks.push(value);
    }
  } finally { await reader.cancel().catch(() => {}); }
  if (length !== expectedBytes) throw new Error('Snapshot extent mismatch');
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return bytes.buffer;
}
export async function sha256(bytes) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))]
    .map(byte => byte.toString(16).padStart(2, '0')).join('');
}
export async function loadManifest(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Cannot fetch guest manifest: ${response.status}`);
  const manifest = await response.json();
  if (manifest.schema !== 1 || manifest.guestAbi !== 1 || manifest.architecture !== 'i386-linux-musl' ||
      !/^[0-9a-f]{64}$/.test(manifest.buildKey) || !manifest.assets) throw new Error('Unsupported guest manifest');
  return manifest;
}
export function assetsFor(manifest, base) {
  const pending = new Map();
  return async function verified(name) {
    if (pending.has(name)) return pending.get(name);
    const record = manifest.assets[name];
    if (!record || !/^[0-9a-f]{64}$/.test(record.sha256) || !Number.isSafeInteger(record.bytes) ||
        record.bytes <= 0 || record.bytes > MAX_ASSET_BYTES || name.startsWith('/') || name.split('/').includes('..')) {
      throw new Error(`Invalid guest asset: ${name}`);
    }
    const url = new URL(name, base);
    if (url.origin !== new URL(base).origin) throw new Error('Guest asset crosses origins');
    const result = (async () => {
      const response = await fetch(url);
      if (!response.ok) throw new Error(`Cannot fetch ${name}: ${response.status}`);
      const chunks = [];
      let length = 0;
      const reader = response.body.getReader();
      try {
        while (true) {
          const {done, value} = await reader.read();
          if (done) break;
          length += value.length;
          if (length > record.bytes) throw new Error(`Guest asset exceeds manifest size: ${name}`);
          chunks.push(value);
        }
      } finally { await reader.cancel(); }
      if (length !== record.bytes) throw new Error(`Guest asset size mismatch: ${name}`);
      const bytes = new Uint8Array(length);
      let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
      if (await sha256(bytes) !== record.sha256) throw new Error(`Guest asset SHA-256 mismatch: ${name}`);
      return bytes;
    })();
    pending.set(name, result);
    return result;
  };
}
