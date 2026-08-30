// One `nupp.workers` lane: a module Web Worker holding its own Lua 5.1 Wasm state.
//
// The lane boots the same verified application manifest the page did, but names the
// workers runtime as the payload's entry, so the bundle runs the scheduler loop
// instead of the application's own entry module. Tasks arrive and replies leave as
// copies through the ordinary browser effect framing; this file relays them and
// never reads the payload the Nupp codec wrote.

import { runPackagedNuppWasmApp } from "./app-runtime.mjs";

const inbox = [];
let deliver;
let current;
let booted = false;

// A Worker only sees a posted message on a fresh turn of its event loop, so asking
// whether cancellation was requested costs one. A MessageChannel gives that turn
// without the nested-timeout clamping `setTimeout(0)` picks up.
function nextTurn() {
  return new Promise((resolve) => {
    const channel = new MessageChannel();
    channel.port1.onmessage = () => {
      channel.port1.close();
      resolve();
    };
    channel.port2.postMessage(0);
  });
}

function nextTask() {
  const assigned = inbox.shift();
  if (assigned) return Promise.resolve(assigned);

  return new Promise((resolve) => {
    deliver = resolve;
  });
}

function assign(task) {
  if (deliver) {
    const resolve = deliver;
    deliver = undefined;
    resolve(task);
    return;
  }
  inbox.push(task);
}

self.addEventListener("message", (event) => {
  const message = event.data;
  if (message?.type === "boot") {
    if (booted) return;
    booted = true;
    boot(message).catch((error) => {
      self.postMessage({type: "failed", error: String(error?.message || error)});
    });
    return;
  }
  if (message?.type === "task") {
    assign(message.task);
    return;
  }
  if (message?.type === "cancel") {
    if (current && current.id === message.id) {
      current.cancelled = true;
      current.deadline = message.deadline === true;
      return;
    }
    // Still queued here, so nothing has loaded or invoked its function.
    const at = inbox.findIndex((task) => task.id === message.id);
    if (at >= 0) {
      const [task] = inbox.splice(at, 1);
      self.postMessage({type: "reply", id: task.id, status: "cancelled", deadline: message.deadline === true});
    }
  }
  // The pool ends a lane by terminating its Worker; there is no close message,
  // and a lane holds nothing a terminate would lose.
});

async function performLaneEffect(effect) {
  if (effect.operation === "checkpoint") {
    await nextTurn();

    return {cancelled: current?.cancelled === true, deadline: current?.deadline === true};
  }
  if (effect.operation === "reply") {
    if (current && current.id === effect.task) {
      self.postMessage({
        type: "reply",
        id: effect.task,
        status: effect.status,
        payload: effect.payload,
        error: effect.error,
        deadline: effect.deadline === true,
      });
      current = undefined;
    }
  } else if (effect.operation !== "next") {
    throw new Error(`unsupported browser worker lane operation ${effect.operation}`);
  }
  const task = await nextTask();
  if (!task) return {};
  current = {id: task.id, cancelled: false, deadline: false};
  self.postMessage({type: "started", id: task.id});

  return {task: task.id, module: task.module, member: task.member, payload: task.payload};
}

// A lane runs for as long as the pool keeps it, so its effect budget belongs to one
// task rather than to the whole run. Every frame that hands it work begins a turn.
function beginsTask(request) {
  return request?.kind === "effects" && (request.requests || []).some(
    (effect) => effect.kind === "lane" && effect.operation !== "checkpoint",
  );
}

async function boot(message) {
  await runPackagedNuppWasmApp(message.manifestUrl, {
    limits: message.limits,
    initialize: new TextEncoder().encode(
      `rawset(_G, "__nuppWorkerEntry", ${JSON.stringify(message.entry || "nupp.workers")})`,
    ),
    // A lane has no pool of its own: the page owns the one pool, and a worker task
    // that opened a scope would be a lane waiting on itself. `nupp.workers` refuses
    // that in the lane's own state; this keeps the host from offering it either.
    workers: false,
    effectHandlers: {lane: performLaneEffect},
    resetLimits: beginsTask,
  });
}
