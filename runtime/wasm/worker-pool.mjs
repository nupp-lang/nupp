// The page-side half of `nupp.workers` for a browser application.
//
// A lane is a module Web Worker booting the same verified application manifest in
// its own Lua 5.1 Wasm state, so nothing is shared between lanes and the page: no
// Wasm threads, no SharedArrayBuffer, and no cross-origin isolation headers. Work
// and results cross as copies inside the ordinary browser effect framing, where
// this file only relays the opaque payload the Nupp codec wrote.
//
// The pool belongs to the running application rather than to one scope, so short
// repeated scopes reuse booted lanes instead of paying a Wasm instantiation each.

const DEFAULT_MAX_LANES = 8;
const LANE_ENTRY_MODULE = "nupp.workers";

function laneCount(maxLanes) {
  const requested = Number.isInteger(maxLanes) && maxLanes > 0 ? maxLanes : DEFAULT_MAX_LANES;
  const available = Number.isInteger(globalThis.navigator?.hardwareConcurrency)
    ? globalThis.navigator.hardwareConcurrency
    : 4;

  return Math.max(1, Math.min(requested, available, 64));
}

export function createWorkerPool({laneUrl, manifestUrl, maxLanes, limits, WorkerClass}) {
  const Worker = WorkerClass || globalThis.Worker;
  if (typeof Worker !== "function") {
    throw new Error("Web Workers are unavailable, so this host cannot run Nupp worker tasks");
  }
  const lanes = [];
  const capacity = laneCount(maxLanes);
  const tasks = new Map();
  const queue = [];
  let started = [];
  let closed = false;

  const drainStarted = () => {
    const reported = started;
    started = [];

    return reported;
  };

  // A settled task stays in the table until it is awaited: `Task:await` is what
  // carries the reply into the application's Lua state, and a scope may leave one
  // unawaited until it closes. The Lua side bounds how many may be outstanding.
  const settle = (task, result) => {
    if (task.settled) return;
    task.settled = true;
    if (task.timer !== undefined) clearTimeout(task.timer);
    task.lane = undefined;
    task.result = result;
    const waiting = task.waiters;
    task.waiters = [];
    for (const resolve of waiting) resolve(result);
  };

  const laneFailure = (lane, reason) => {
    const running = lane.task;
    lane.task = undefined;
    lane.worker.terminate();
    const at = lanes.indexOf(lane);
    if (at >= 0) lanes.splice(at, 1);
    if (running) settle(running, {status: "failed", error: reason});
    dispatch();
  };

  const laneMessage = (lane, message) => {
    if (message?.type === "started") {
      if (lane.task && lane.task.id === message.id) started.push(message.id);
      return;
    }
    if (message?.type === "failed") {
      laneFailure(lane, `nupp: a worker lane could not start: ${message.error}`);
      return;
    }
    if (message?.type !== "reply" || !Number.isInteger(message.id)) return;
    const task = lane.task && lane.task.id === message.id ? lane.task : tasks.get(message.id);
    lane.task = undefined;
    if (task) {
      settle(task, message.status === "done"
        ? {status: "done", payload: message.payload}
        : message.status === "cancelled"
          ? {status: "cancelled", deadline: message.deadline === true}
          : {status: "failed", error: message.error || "worker task failed without an error"});
    }
    dispatch();
  };

  const openLane = () => {
    const worker = new Worker(laneUrl, {type: "module"});
    const lane = {worker, task: undefined};
    worker.addEventListener("message", (event) => laneMessage(lane, event.data));
    worker.addEventListener("error", (event) => laneFailure(
      lane, `nupp: a worker lane ended before answering a task: ${event.message || event.type}`,
    ));
    worker.addEventListener("messageerror", () => laneFailure(
      lane, "nupp: a worker lane could not decode a task",
    ));
    worker.postMessage({type: "boot", manifestUrl, entry: LANE_ENTRY_MODULE, limits});
    lanes.push(lane);

    return lane;
  };

  function dispatch() {
    while (queue.length > 0 && !closed) {
      let lane = lanes.find((candidate) => candidate.task === undefined);
      if (!lane && lanes.length < capacity) lane = openLane();
      if (!lane) return;
      const task = queue.shift();
      if (task.settled) continue;
      lane.task = task;
      task.lane = lane;
      lane.worker.postMessage({
        type: "task",
        task: {id: task.id, module: task.module, member: task.member, payload: task.payload},
      });
      if (task.cancelRequested) {
        lane.worker.postMessage({type: "cancel", id: task.id, deadline: task.deadline === true});
      }
    }
  }

  const requestCancel = (task, deadline) => {
    if (task.settled) return;
    task.cancelRequested = true;
    task.deadline = task.deadline || deadline === true;
    if (task.lane) {
      task.lane.worker.postMessage({type: "cancel", id: task.id, deadline: task.deadline === true});
      return;
    }
    // Never handed to a lane, so nothing loaded or invoked its function.
    const at = queue.indexOf(task);
    if (at >= 0) queue.splice(at, 1);
    settle(task, {status: "cancelled", deadline: task.deadline === true});
  };

  const accept = (entry) => {
    if (!Number.isInteger(entry?.task) || typeof entry.module !== "string" ||
        typeof entry.member !== "string" || typeof entry.payload !== "string") {
      throw new Error("invalid browser worker submission");
    }
    if (tasks.has(entry.task)) throw new Error("a browser worker task id was reused");
    const task = {
      id: entry.task,
      module: entry.module,
      member: entry.member,
      payload: entry.payload,
      settled: false,
      cancelRequested: false,
      deadline: false,
      waiters: [],
      lane: undefined,
      timer: undefined,
      result: undefined,
    };
    tasks.set(task.id, task);
    queue.push(task);
    // The scope's absolute deadline is a reading of the same monotonic clock the
    // application's own `nupp.time.now` returns, because both are this Worker's.
    if (typeof entry.deadline === "number" && Number.isFinite(entry.deadline)) {
      task.timer = setTimeout(
        () => requestCancel(task, true),
        Math.max(0, entry.deadline - performance.now()),
      );
    }
  };

  // Submissions arrive in one message however many there are, and one that cannot
  // be framed fails as itself rather than taking the rest of the batch with it.
  const submit = (effect) => {
    if (closed) throw new Error("the browser worker pool is closed");
    if (!Array.isArray(effect.tasks)) throw new Error("invalid browser worker submission");
    const rejected = [];
    for (const entry of effect.tasks) {
      try {
        accept(entry);
      } catch (error) {
        rejected.push({task: entry?.task, error: String(error?.message || error)});
      }
    }
    dispatch();

    return {lanes: capacity, rejected, started: drainStarted()};
  };

  const settlement = async (effect) => {
    const task = tasks.get(effect.task);
    if (!task) throw new Error("a browser worker task was awaited twice or never submitted");
    const result = task.settled
      ? task.result
      : await new Promise((resolve) => task.waiters.push(resolve));
    tasks.delete(task.id);

    return {...result, started: drainStarted()};
  };

  return {
    perform(effect) {
      if (effect.operation === "submit") return submit(effect);
      if (effect.operation === "await") return settlement(effect);
      if (effect.operation === "cancel") {
        const task = tasks.get(effect.task);
        if (task) requestCancel(task, false);
        return {started: drainStarted()};
      }
      if (effect.operation === "lanes") return {lanes: capacity, started: drainStarted()};
      throw new Error(`unsupported browser worker operation ${effect.operation}`);
    },
    close() {
      if (closed) return;
      closed = true;
      for (const task of [...tasks.values()]) {
        settle(task, {status: "failed", error: "nupp: the browser worker pool closed"});
      }
      for (const lane of lanes.splice(0, lanes.length)) lane.worker.terminate();
    },
  };
}
