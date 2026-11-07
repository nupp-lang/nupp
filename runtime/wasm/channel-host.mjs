// One host-side endpoint table per Nupp guest. Only startup framing carries
// ports between these tables. Ordinary traffic stays on the data ports.
import {createPortChannel, adoptPortEndpoint} from './channel.mjs';

const MAX_WIRE_BYTES = 512 * 1024;

function bytes(text) {
  if (typeof text !== 'string') throw new TypeError('invalid channel payload');
  if (text.length > Math.ceil(MAX_WIRE_BYTES / 3) * 4) throw new RangeError('browser channel payload exceeds 512 KiB');
  const raw = atob(text);
  const value = Uint8Array.from(raw, character => character.charCodeAt(0));
  if (value.length > MAX_WIRE_BYTES) throw new RangeError('browser channel payload exceeds 512 KiB');
  return value;
}

function encoded(value) {
  let text = '';
  for (let offset = 0; offset < value.length; offset += 8192) {
    text += String.fromCharCode(...value.subarray(offset, offset + 8192));
  }
  return btoa(text);
}

export function createChannelHost({MessageChannelClass = globalThis.MessageChannel} = {}) {
  const entries = new Map();
  const supervisors = new Map();
  const resources = new Map();
  let nextId = 1;
  let nextToken = 1;
  let cancelled = false;
  let deadline = false;
  let closed = false;

  const description = entry => {
    const state = entry.endpoint.inspect();
    return {handle: entry.id, direction: entry.endpoint.direction,
      messages: entry.messages, bytes: entry.bytes,
      closed: state.closed && (entry.endpoint.direction === 'sender' || state.queued === 0),
      sent: entry.sent, sentBytes: entry.sentBytes,
      consumed: entry.sent - (entry.messages - state.availableMessages),
      consumedBytes: entry.sentBytes - (entry.bytes - state.availableBytes)};
  };

  function finishSupervisor(token) {
    const item = supervisors.get(token);
    if (!item) return;
    item.done = true;
    const peer = supervisors.get(item.peer);
    if (!peer || peer.done) {
      item.port.close();
      supervisors.delete(token);
      if (peer) { peer.port.close(); supervisors.delete(item.peer); }
      resources.delete(item.resource);
    }
  }

  function revoke(token) {
    const item = supervisors.get(token);
    if (!item || item.done) return;
    const peer = supervisors.get(item.peer);
    peer?.port.postMessage({type: 'remote-close'});
    finishSupervisor(token);
  }

  function install(endpoint, control, token, messages, byteLimit, sent = 0, sentBytes = 0, resource = null) {
    const id = nextId++;
    const entry = {id, endpoint, control, token, messages, bytes: byteLimit, sent, sentBytes, watch: null, resource};
    entries.set(id, entry);
    resource?.ids.add(id);
    entry.controlMessage = event => {
      if (event.data?.type === 'remote-close') endpoint.remoteClose();
      if (event.data?.type === 'abort') drop(id);
    };
    control.addEventListener('message', entry.controlMessage);
    control.start?.();
    return entry;
  }

  function find(id) {
    const entry = entries.get(id);
    if (!entry) throw new Error('invalid, closed, or moved channel endpoint');
    return entry;
  }

  function drop(id) {
    const entry = entries.get(id);
    if (!entry) return;
    entries.delete(id);
    entry.resource?.ids.delete(id);
    entry.endpoint.close();
    entry.watch?.finish({closed: true});
    entry.control.postMessage({type: 'closed'});
    entry.control.close();
  }

  function create(effect) {
    const pair = createPortChannel(effect.messages, effect.bytes, MessageChannelClass);
    const sending = new MessageChannelClass();
    const receiving = new MessageChannelClass();
    const senderToken = nextToken++;
    const receiverToken = nextToken++;
    const resource = {id: senderToken, tokens: [senderToken, receiverToken], ids: new Set()};
    resources.set(resource.id, resource);
    for (const [token, peer, port] of [
      [senderToken, receiverToken, sending.port1], [receiverToken, senderToken, receiving.port1],
    ]) {
      supervisors.set(token, {port, peer, done: false, resource: resource.id});
      port.addEventListener('message', event => {
        if (event.data?.type === 'closed') finishSupervisor(token);
      });
      port.start?.();
    }
    const sender = install(pair.sender, sending.port2, senderToken, effect.messages, effect.bytes, 0, 0, resource);
    const receiver = install(pair.receiver, receiving.port2, receiverToken, effect.messages, effect.bytes, 0, 0, resource);
    return {sender: description(sender), receiver: description(receiver), resource: resource.id};
  }

  function release(resourceId) {
    const resource = resources.get(resourceId);
    if (!resource) return;
    for (const id of resource.ids) drop(id);
    for (const token of resource.tokens) supervisors.get(token)?.port.postMessage({type: 'abort'});
    for (const token of resource.tokens) finishSupervisor(token);
    resources.delete(resourceId);
  }

  function watch(entry, effect) {
    if (entry.watch) throw new Error('a channel endpoint already has a host watch');
    return new Promise(resolve => {
      let unsubscribe = () => {};
      let finished = false;
      const finish = value => {
        if (finished) return;
        finished = true;
        unsubscribe();
        entry.watch = null;
        resolve(value);
      };
      const poll = () => {
        if (cancelled) { finish({cancelled: true, deadline}); return; }
        const state = description(entry);
        if (entry.endpoint.direction === 'sender') {
          if (state.closed || state.consumed !== effect.consumed || state.consumedBytes !== effect.consumedBytes) {
            finish(state);
          }
        } else {
          const packet = entry.endpoint.peek();
          if (packet.status === 'value') finish({...state, payload: encoded(packet.value)});
          else if (packet.status === 'closed') finish({...state, closed: true});
        }
      };
      entry.watch = {finish};
      unsubscribe = entry.endpoint.observe(poll);
      poll();
    });
  }

  return {
    perform(effect) {
      if (closed) throw new Error('the channel host is closed');
      if (effect.operation === 'create') return create(effect);
      if (effect.operation === 'release') {
        for (const resource of effect.resources || [effect.resource]) release(resource);
        return {};
      }
      if (effect.operation === 'close') { drop(effect.handle); return {}; }
      const entry = find(effect.handle);
      if (effect.operation === 'send') {
        const payload = bytes(effect.payload);
        const result = entry.endpoint.trySend(payload);
        if (result.status === 'sent') { entry.sent += 1; entry.sentBytes += payload.length; }
        else if (result.status !== 'closed') throw new Error('channel credit accounting disagrees with the guest');
        return {...description(entry), status: result.status};
      }
      if (effect.operation === 'consume') {
        const packet = entry.endpoint.tryReceive();
        if (packet.status !== 'value') throw new Error('a staged channel message is missing');
        return {};
      }
      if (effect.operation === 'watch') return watch(entry, effect);
      throw new Error(`unsupported channel operation ${effect.operation}`);
    },
    take(ids) {
      if (!Array.isArray(ids) || new Set(ids).size !== ids.length) throw new Error('invalid endpoint startup list');
      const found = ids.map(find);
      const snapshots = [];
      try {
        for (const entry of found) {
          entry.watch?.finish({moved: true});
          entry.control.removeEventListener('message', entry.controlMessage);
          const snapshot = entry.endpoint.move();
          snapshots.push({snapshot, control: entry.control, token: entry.token,
            sent: entry.sent, sentBytes: entry.sentBytes});
          entries.delete(entry.id);
          entry.resource?.ids.delete(entry.id);
        }
        return snapshots;
      } catch (error) {
        for (const item of snapshots) { adoptPortEndpoint(item.snapshot).close(); item.control.postMessage({type: 'closed'}); item.control.close(); }
        for (const entry of found) drop(entry.id);
        throw error;
      }
    },
    adopt(snapshots) {
      const adopted = [];
      try {
        for (const item of snapshots || []) {
          const endpoint = adoptPortEndpoint(item.snapshot);
          adopted.push(install(endpoint, item.control, item.token, item.snapshot.messages,
            item.snapshot.bytes, item.sent, item.sentBytes));
        }
        return adopted.map(description);
      } catch (error) {
        for (const entry of adopted) drop(entry.id);
        for (const item of (snapshots || []).slice(adopted.length)) {
          try { adoptPortEndpoint(item.snapshot).close(); } catch {}
          item.control.postMessage({type: 'closed'}); item.control.close();
        }
        throw error;
      }
    },
    revoke,
    discard(snapshots) {
      for (const item of snapshots || []) {
        try { adoptPortEndpoint(item.snapshot).close(); } catch {}
        try { item.control.postMessage({type: 'closed'}); } catch {}
        item.control.close();
        revoke(item.token);
      }
    },
    interrupt(isDeadline = false) {
      cancelled = true;
      deadline = isDeadline;
      for (const entry of entries.values()) entry.watch?.finish({cancelled: true, deadline});
    },
    reset() { cancelled = deadline = false; },
    settle() { for (const id of entries.keys()) drop(id); },
    close() {
      if (closed) return;
      closed = true;
      for (const id of entries.keys()) drop(id);
      for (const token of supervisors.keys()) revoke(token);
      for (const item of supervisors.values()) item.port.close();
      supervisors.clear();
      resources.clear();
    },
    inspect() { return {endpoints: entries.size, supervisors: supervisors.size, resources: resources.size,
      watches: [...entries.values()].filter(entry => entry.watch).length}; },
  };
}

export function endpointTransfers(snapshots) {
  return snapshots.flatMap(item => [item.snapshot.port, item.control,
    ...item.snapshot.queue.map(value => value.buffer)]);
}
