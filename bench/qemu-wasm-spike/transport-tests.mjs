import assert from 'node:assert/strict';
import {leaseAdapter} from '../../build/qemu-wasm-spike/web/guest-runtime.mjs';
import {handleBrowserEffects} from '../../runtime/wasm/app-runtime.mjs';

// Test against the real HTTP handler, including its release-on-failure path.
for (const scenario of ['writable', 'readonly', 'stale', 'wrong-size']) {
  const adapter = leaseAdapter([{id: 7, bytes: 4, data: new ArrayBuffer(4), writable: scenario !== 'readonly'}]);
  if (scenario === 'stale') adapter.module._nupp_wasm_release_lease(7);
  const options = {wasmModule: adapter.module,
    httpBodies: new Map([[1, {length: scenario === 'wrong-size' ? 5 : 4, chunks: [new Uint8Array([0, 255, 1, 128])]}]])};
  const {responses: [response]} = await handleBrowserEffects({kind: 'effects', requests: [
    {id: 1, kind: 'http', operation: 'read-body', body: 1, lease: 7},
  ]}, options);
  assert.equal(response.ok, scenario === 'writable', scenario);
  assert.equal(options.httpBodies.size, 0, scenario);
  assert.equal(adapter.module._nupp_wasm_lease_address(7), 0, scenario);
  if (response.ok) assert.deepEqual([...new Uint8Array(adapter.writes()[0].data)], [0, 255, 1, 128]);
  if (scenario === 'readonly') assert.deepEqual(adapter.writes(), []);
}
assert.throws(() => leaseAdapter([{id: 1, bytes: 2, data: new ArrayBuffer(1)}]), /Invalid/);
assert.throws(() => leaseAdapter([{id: 1, bytes: 0, data: new ArrayBuffer(0)}, {id: 1, bytes: 0, data: new ArrayBuffer(0)}]), /Invalid/);
assert.throws(() => leaseAdapter([{id: 1, bytes: 18 * 1024 * 1024, data: new ArrayBuffer(18 * 1024 * 1024)}]), /limit/);
console.log('Passed transfer writeback, read-only, stale, size, release, duplicate, and allocation-limit checks');
