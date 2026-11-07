import assert from "node:assert/strict";
import test from "node:test";
import {createPortChannel, adoptPortEndpoint} from "../../../../runtime/wasm/channel.mjs";

const turn = () => new Promise(resolve => setTimeout(resolve, 5));
async function until(predicate) {
  for (let attempts = 0; attempts < 100; attempts++) {
    if (predicate()) return;
    await turn();
  }
  assert.fail("channel readiness did not arrive");
}

function pair(t, messages, bytes) {
  const channel = createPortChannel(messages, bytes);
  t.after(() => { channel.sender.close(); channel.receiver.close(); });
  return channel;
}

test("port credits bound accepted packets before the receiver event loop runs", async t => {
  const {sender, receiver} = pair(t, 2, 5);
  assert.equal(sender.trySend(Uint8Array.of(1, 2, 3)).status, "sent");
  assert.equal(sender.trySend(Uint8Array.of(4, 5)).status, "sent");
  const unsent = new Uint8Array();
  assert.deepEqual(sender.trySend(unsent), {status: "full", value: unsent});
  assert.equal(receiver.inspect().queued, 0);
  assert.equal(sender.inspect().availableBytes, 0);
  await until(() => receiver.inspect().queued === 2);
  assert.equal(receiver.inspect().retainedBytes, 5);
  assert.deepEqual(receiver.tryReceive(), {status: "value", value: Uint8Array.of(1, 2, 3)});
  assert.equal(sender.trySend(Uint8Array.of(6)).status, "full");
  await until(() => sender.inspect().availableMessages === 1);
  assert.equal(sender.trySend(Uint8Array.of(6, 7, 8)).status, "sent");
  assert.equal(sender.inspect().availableBytes, 0);
});

test("oversized sends fail without consuming credits or copying input", t => {
  const {sender} = pair(t, 1, 1);
  const input = Uint8Array.of(1, 2);
  assert.throws(() => sender.trySend(input), /byte limit/);
  assert.deepEqual(input, Uint8Array.of(1, 2));
  assert.equal(sender.inspect().availableMessages, 1);
  assert.equal(sender.inspect().availableBytes, 1);
});

test("closing ingress drains accepted packets including zero-byte messages", async t => {
  const {sender, receiver} = pair(t, 2, 1);
  sender.trySend(new Uint8Array());
  sender.trySend(Uint8Array.of(42));
  sender.close();
  await until(() => receiver.inspect().closed);
  assert.equal(receiver.tryReceive().value.byteLength, 0);
  assert.deepEqual(receiver.tryReceive().value, Uint8Array.of(42));
  assert.equal(receiver.tryReceive().status, "closed");
});

test("receiver close discards queued and in-flight packets and wakes senders", async t => {
  const {sender, receiver} = pair(t, 1, 1);
  sender.trySend(Uint8Array.of(1));
  let woke = 0;
  const unsubscribe = sender.subscribe(() => woke++, 1);
  assert.equal(sender.inspect().waits, 1);
  receiver.close();
  await until(() => woke === 1);
  assert.equal(receiver.inspect().retainedBytes, 0);
  assert.equal(receiver.inspect().queued, 0);
  assert.equal(sender.trySend(Uint8Array.of(2)).status, "closed");
  unsubscribe();
  assert.equal(sender.inspect().waits, 0);
});

test("moving endpoints invalidates stale wrappers and transfer snapshots", async t => {
  const {sender, receiver} = pair(t, 2, 2);
  sender.trySend(Uint8Array.of(1));
  await until(() => receiver.inspect().queued === 1);
  const saved = receiver.move();
  const moved = adoptPortEndpoint(saved);
  t.after(() => moved.close());
  assert.throws(() => receiver.tryReceive(), /moved/);
  assert.throws(() => adoptPortEndpoint(saved), /stale/);
  receiver.close();
  assert.deepEqual(moved.tryReceive().value, Uint8Array.of(1));
  const next = moved.move();
  assert.throws(() => adoptPortEndpoint(saved), /stale/);
  const final = adoptPortEndpoint(next);
  t.after(() => final.close());
  assert.equal(sender.trySend(Uint8Array.of(2)).status, "sent");
  await until(() => final.inspect().queued === 1);
  assert.deepEqual(final.tryReceive().value, Uint8Array.of(2));
});

test("readiness subscriptions are removable and do not retain send payloads", async t => {
  const {sender, receiver} = pair(t, 1, 1);
  let woke = 0;
  const unsubscribe = receiver.subscribe(() => woke++);
  unsubscribe();
  sender.trySend(Uint8Array.of(1));
  await until(() => receiver.inspect().queued === 1);
  assert.equal(woke, 0);
  assert.equal(receiver.inspect().waits, 0);
  receiver.subscribe(() => woke++);
  assert.equal(woke, 1);
});
