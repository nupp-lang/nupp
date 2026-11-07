import test from 'node:test';
import assert from 'node:assert/strict';
import {createChannelHost, endpointTransfers} from '../../../../runtime/wasm/channel-host.mjs';

const turn = () => new Promise(resolve => setTimeout(resolve, 5));
const packet = text => btoa(text);

test('staging retains credits until the Nupp receiver consumes a packet', async () => {
  const host = createChannelHost();
  try {
    const {sender, receiver} = host.perform({operation: 'create', messages: 2, bytes: 4});
    assert.equal(host.perform({operation: 'send', handle: sender.handle, payload: packet('ab')}).status, 'sent');
    const staged = await host.perform({operation: 'watch', handle: receiver.handle});
    assert.equal(atob(staged.payload), 'ab');
    let credits = host.perform({operation: 'send', handle: sender.handle, payload: packet('cd')});
    assert.equal(credits.consumed, 0);
    assert.throws(() => host.perform({operation: 'send', handle: sender.handle, payload: packet('e')}), /credit accounting/);
    host.perform({operation: 'consume', handle: receiver.handle});
    credits = await host.perform({operation: 'watch', handle: sender.handle, consumed: 0, consumedBytes: 0});
    assert.equal(credits.consumed, 1);
    assert.equal(credits.consumedBytes, 2);
    const second = await host.perform({operation: 'watch', handle: receiver.handle});
    assert.equal(atob(second.payload), 'cd');
    host.perform({operation: 'close', handle: sender.handle});
    host.perform({operation: 'consume', handle: receiver.handle});
    assert.equal((await host.perform({operation: 'watch', handle: receiver.handle})).closed, true);
    host.perform({operation: 'close', handle: receiver.handle});
    await turn();
    assert.deepEqual(host.inspect(), {endpoints: 0, supervisors: 0, resources: 0, watches: 0});
  } finally { host.close(); }
});

test('startup transfer preserves queued packets, credit debt, and binary bytes', async () => {
  const parent = createChannelHost();
  const service = createChannelHost();
  try {
    const {sender, receiver} = parent.perform({operation: 'create', messages: 1, bytes: 4});
    parent.perform({operation: 'send', handle: sender.handle, payload: packet('\0\xff')});
    await parent.perform({operation: 'watch', handle: receiver.handle});
    const pending = parent.perform({operation: 'watch', handle: sender.handle, consumed: 0, consumedBytes: 0});
    const snapshots = parent.take([sender.handle, receiver.handle]);
    assert.equal((await pending).moved, true);
    assert.throws(() => parent.perform({operation: 'send', handle: sender.handle, payload: ''}), /moved/);
    const transported = structuredClone(snapshots, {transfer: endpointTransfers(snapshots)});
    const [sending, receiving] = service.adopt(transported);
    assert.equal(atob((await service.perform({operation: 'watch', handle: receiving.handle})).payload), '\0\xff');
    service.perform({operation: 'consume', handle: receiving.handle});
    const credit = await service.perform({operation: 'watch', handle: sending.handle, consumed: 0, consumedBytes: 0});
    assert.equal(credit.consumed, 1);
    service.perform({operation: 'close', handle: sending.handle});
    service.perform({operation: 'close', handle: receiving.handle});
    await turn();
    assert.equal(parent.inspect().supervisors, 0);
  } finally { service.close(); parent.close(); }
});

test('supervision closes a failed owner’s peer and cancellation settles watches', async () => {
  const parent = createChannelHost();
  const service = createChannelHost();
  try {
    const {sender, receiver} = parent.perform({operation: 'create', messages: 1, bytes: 4});
    const snapshots = parent.take([sender.handle]);
    const [sending] = service.adopt(structuredClone(snapshots, {transfer: endpointTransfers(snapshots)}));
    const waiting = parent.perform({operation: 'watch', handle: receiver.handle});
    parent.revoke(snapshots[0].token);
    assert.equal((await waiting).closed, true);
    const sleeping = service.perform({operation: 'watch', handle: sending.handle, consumed: 0, consumedBytes: 0});
    service.interrupt(true);
    assert.deepEqual(await sleeping, {cancelled: true, deadline: true});
    assert.equal(service.inspect().watches, 0);
  } finally { service.close(); parent.close(); }
});

test('scope release discards storage and closes endpoints after a startup move', async () => {
  const parent = createChannelHost();
  const service = createChannelHost();
  try {
    const {sender, receiver, resource} = parent.perform({operation: 'create', messages: 1, bytes: 8});
    const snapshots = parent.take([sender.handle]);
    const [sending] = service.adopt(structuredClone(snapshots, {transfer: endpointTransfers(snapshots)}));
    service.perform({operation: 'send', handle: sending.handle, payload: btoa('held')});
    await parent.perform({operation: 'watch', handle: receiver.handle});
    const waiting = service.perform({operation: 'watch', handle: sending.handle, consumed: 0, consumedBytes: 0});
    parent.perform({operation: 'release', resources: [resource]});
    assert.equal((await waiting).closed, true);
    await turn();
    assert.deepEqual(parent.inspect(), {endpoints: 0, supervisors: 0, resources: 0, watches: 0});
    assert.deepEqual(service.inspect(), {endpoints: 0, supervisors: 0, resources: 0, watches: 0});
  } finally { service.close(); parent.close(); }
});
