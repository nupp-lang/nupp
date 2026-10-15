// A frame carries copies of bounded guest leases, never guest addresses.
export function createTransfers(descriptors = [], payload = new ArrayBuffer(0)) {
  if (!Array.isArray(descriptors) || descriptors.length > 256 || payload.byteLength > 2 * 1024 * 1024)
    throw new Error('Invalid guest transfer batch');
  const bytes = new Uint8Array(payload), leases = new Map();
  let end = 0;
  for (const item of descriptors) {
    if (!Number.isSafeInteger(item.id) || item.id <= 0 || leases.has(item.id) ||
        !Number.isSafeInteger(item.offset) || item.offset !== end ||
        !Number.isSafeInteger(item.bytes) || item.bytes < 0 ||
        item.bytes > bytes.length - end || typeof item.writable !== 'boolean')
      throw new Error('Invalid guest transfer descriptor');
    leases.set(item.id, {...item, view: bytes.subarray(end, end + item.bytes), released: false});
    end += item.bytes;
  }
  if (end !== bytes.length) throw new Error('Unclaimed guest transfer bytes');
  return {
    lease(id, expectedBytes, writable) {
      const entry = leases.get(id);
      if (!entry || entry.released || expectedBytes !== undefined && entry.bytes !== expectedBytes || writable && !entry.writable)
        throw new Error('Guest transfer lease is stale or has the wrong extent or access');
      return entry;
    },
    release(id) { const entry = leases.get(id); if (entry) entry.released = true; },
    response() {
      let offset = 0;
      const returned = [], pieces = [];
      for (const entry of leases.values()) {
        if (!entry.released) throw new Error('Browser operation retained a guest transfer lease');
        const item = {id: entry.id};
        if (entry.writable) {
          Object.assign(item, {offset, bytes: entry.bytes});
          pieces.push(entry.view); offset += entry.bytes;
        }
        returned.push(item);
      }
      const payload = new Uint8Array(offset);
      offset = 0;
      for (const piece of pieces) { payload.set(piece, offset); offset += piece.length; }
      return {leases: returned, payload};
    },
  };
}
