// Private SPSC transport. Credits cover accepted packets until consumption,
// including packets queued by MessagePort rather than by this receiver.
// Waiting belongs to each guest's effect loop; try operations retain no waiter.

const identities = new WeakMap();

function limits(messages, bytes) {
  if (!Number.isSafeInteger(messages) || messages <= 0 ||
      !Number.isSafeInteger(bytes) || bytes <= 0) {
    throw new RangeError("channel limits must be positive safe integers");
  }
}

function endpoint(port, direction, messages, bytes, saved = {}) {
  limits(messages, bytes);
  if (!port || typeof port.postMessage !== "function" ||
      typeof port.addEventListener !== "function" || typeof port.close !== "function") {
    throw new TypeError("a channel endpoint needs a MessagePort");
  }
  if (direction !== "sender" && direction !== "receiver") {
    throw new TypeError("invalid channel endpoint direction");
  }
  let identity = identities.get(port);
  if (identity && (identity.claimed || saved.generation !== identity.generation)) {
    throw new Error("invalid or stale channel endpoint transfer");
  }
  const queued = saved.queue ?? [];
  const savedSlots = saved.slots ?? messages;
  const savedRoom = saved.room ?? bytes;
  const savedRetained = saved.retained ?? 0;
  let queuedBytes = 0;
  if (!Array.isArray(queued) || queued.length > messages ||
      !Number.isSafeInteger(savedSlots) || savedSlots < 0 || savedSlots > messages ||
      !Number.isSafeInteger(savedRoom) || savedRoom < 0 || savedRoom > bytes ||
      !Number.isSafeInteger(savedRetained) || savedRetained < 0 || savedRetained > bytes) {
    throw new TypeError("invalid channel endpoint accounting");
  }
  for (const payload of queued) {
    if (!(payload instanceof Uint8Array) || !(payload.buffer instanceof ArrayBuffer) ||
        payload.byteOffset !== 0 || payload.byteLength !== payload.buffer.byteLength) {
      throw new TypeError("invalid queued channel payload");
    }
    queuedBytes += payload.byteLength;
  }
  if (queuedBytes !== savedRetained || (direction === "sender" && queued.length !== 0)) {
    throw new TypeError("invalid retained channel byte count");
  }
  if (!identity) {
    identity = {generation: saved.generation ?? 1, claimed: false};
    identities.set(port, identity);
  }
  if (!Number.isSafeInteger(identity.generation) || identity.generation < 1) {
    throw new Error("invalid channel endpoint generation");
  }
  identity.claimed = true;
  let live = true;
  let closed = saved.closed === true;
  let slots = savedSlots;
  let room = savedRoom;
  let retained = savedRetained;
  let queue = queued;
  const waiters = new Set();
  const observers = new Set();

  const wake = () => {
    const pending = [...waiters];
    waiters.clear();
    for (const resume of pending) resume();
    for (const observe of [...observers]) observe();
  };
  const notify = message => {
    try { port.postMessage(message); } catch { /* The peer is already gone. */ }
  };
  const close = () => {
    if (!live) return;
    live = false;
    closed = true;
    queue = [];
    retained = 0;
    notify({kind: direction === "sender" ? "end" : "stop"});
    port.removeEventListener("message", arrived);
    port.removeEventListener("messageerror", close);
    port.close();
    wake();
  };
  const arrived = event => {
    if (!live) return;
    const packet = event.data;
    if (direction === "sender") {
      if (packet?.kind === "stop") {
        closed = true;
        wake();
      } else if (packet?.kind === "credit" && !closed) {
        if (packet.messages !== 1 || !Number.isSafeInteger(packet.bytes) || packet.bytes < 0 ||
            slots + 1 > messages || room + packet.bytes > bytes) {
          close();
          return;
        }
        slots += 1;
        room += packet.bytes;
        wake();
      } else if (!closed) close();
      return;
    }
    if (packet?.kind === "end") {
      closed = true;
      wake();
      return;
    }
    const payload = packet?.payload;
    if (closed || packet?.kind !== "value" || !(payload instanceof Uint8Array) ||
        !(payload.buffer instanceof ArrayBuffer) || payload.byteOffset !== 0 ||
        payload.byteLength !== payload.buffer.byteLength || queue.length >= messages ||
        retained + payload.byteLength > bytes) {
      close();
      return;
    }
    queue.push(payload);
    retained += payload.byteLength;
    wake();
  };
  port.addEventListener("message", arrived);
  port.addEventListener("messageerror", close);
  port.start?.();

  const ready = () => !live || closed || (direction === "sender" ? slots > 0 : queue.length > 0);
  const handle = {
    direction,
    trySend(payload) {
      if (direction !== "sender" || !live) throw new Error("invalid or moved sender");
      if (!(payload instanceof Uint8Array) || !(payload.buffer instanceof ArrayBuffer)) {
        throw new TypeError("channel payloads must be owned bytes");
      }
      if (payload.byteLength > bytes) throw new RangeError("channel payload exceeds its byte limit");
      if (closed) return {status: "closed", value: payload};
      if (slots === 0 || room < payload.byteLength) return {status: "full", value: payload};
      const size = payload.byteLength;
      // Copy only after checking credits. No serialization staging is retained
      // for a full channel, and transfer releases the sending guest's copy.
      const copy = payload.slice();
      slots -= 1;
      room -= size;
      try {
        port.postMessage({kind: "value", payload: copy}, [copy.buffer]);
      } catch (error) {
        slots += 1;
        room += size;
        close();
        throw error;
      }
      return {status: "sent"};
    },
    tryReceive() {
      if (direction !== "receiver" || !live) throw new Error("invalid or moved receiver");
      const value = queue.shift();
      if (value !== undefined) {
        retained -= value.byteLength;
        if (!closed) notify({kind: "credit", messages: 1, bytes: value.byteLength});
        return {status: "value", value};
      }
      return {status: closed ? "closed" : "empty"};
    },
    // The caller retries before subscribing. Rechecking readiness here closes
    // the event-loop race without retaining a payload or a pending send.
    subscribe(resume, requiredBytes = 0) {
      if (typeof resume !== "function") throw new TypeError("channel readiness needs a callback");
      if (!Number.isSafeInteger(requiredBytes) || requiredBytes < 0 || requiredBytes > bytes) {
        throw new RangeError("invalid channel wait size");
      }
      const available = () => !live || closed || (direction === "sender"
        ? slots > 0 && room >= requiredBytes : queue.length > 0);
      if (available()) {
        resume();
        return () => {};
      }
      waiters.add(resume);
      return () => waiters.delete(resume);
    },
    close,
    // Peeking stages at most one message in the Lua guest. Keep it charged to
    // the channel until the guest actually consumes it with tryReceive.
    peek() {
      if (direction !== "receiver" || !live) throw new Error("invalid or moved receiver");
      if (queue.length > 0) return {status: "value", value: queue[0]};
      return {status: closed ? "closed" : "empty"};
    },
    observe(callback) {
      if (typeof callback !== "function") throw new TypeError("channel observation needs a callback");
      observers.add(callback);
      return () => observers.delete(callback);
    },
    remoteClose() {
      if (!live) return;
      closed = true;
      wake();
    },
    // Snapshot transfer is performed by the host's startup framing, never by a
    // Nupp number or pointer. Moving invalidates the old local wrapper first.
    move() {
      if (!live || waiters.size !== 0 || observers.size !== 0) throw new Error("invalid or waiting channel endpoint");
      if (identity.generation === Number.MAX_SAFE_INTEGER) {
        close();
        throw new Error("channel endpoint generation exhausted");
      }
      live = false;
      port.removeEventListener("message", arrived);
      port.removeEventListener("messageerror", close);
      identity.generation += 1;
      identity.claimed = false;
      const snapshot = {port, direction, messages, bytes, closed, slots, room, retained, queue,
        generation: identity.generation};
      queue = [];
      retained = 0;
      return snapshot;
    },
    inspect() {
      return {live, closed, queued: queue.length, retainedBytes: retained,
        availableMessages: slots, availableBytes: room, waits: waiters.size,
        observations: observers.size, ready: ready()};
    },
  };
  return handle;
}

export function createPortChannel(messages, bytes, MessageChannelClass = globalThis.MessageChannel) {
  limits(messages, bytes);
  const {port1, port2} = new MessageChannelClass();
  return {
    sender: endpoint(port1, "sender", messages, bytes),
    receiver: endpoint(port2, "receiver", messages, bytes),
  };
}

// Only host startup code calls this after it receives transferred MessagePorts.
// Authentication across guests is possession of the actual port, not a wire ID.
export function adoptPortEndpoint(snapshot) {
  if (!snapshot || typeof snapshot.closed !== "boolean" || !Array.isArray(snapshot.queue)) {
    throw new TypeError("invalid channel endpoint transfer");
  }
  return endpoint(snapshot.port, snapshot.direction, snapshot.messages, snapshot.bytes, snapshot);
}
