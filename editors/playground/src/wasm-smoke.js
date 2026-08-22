const output = document.querySelector("#result");
const started = performance.now();
const worker = new Worker(new URL("./worker.js", import.meta.url), {
  type: "module",
});
let nextId = 1;
const pending = new Map();

function fail(reason) {
  output.dataset.status = "failed";
  output.textContent = JSON.stringify({ ok: false, error: String(reason) });
  document.title = "FAIL — Nupp Wasm smoke";
}

function request(kind, values = {}) {
  return new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, { resolve, reject });
    worker.postMessage({ id, kind, ...values });
  });
}

const ready = new Promise((resolve, reject) => {
  worker.addEventListener("message", (event) => {
    const message = event.data;
    if (message.type === "ready") {
      resolve(message.timings);
      return;
    }
    if (message.type === "boot-error") {
      reject(new Error(message.message));
      return;
    }
    if (message.id) {
      const waiter = pending.get(message.id);
      if (!waiter) return;
      pending.delete(message.id);
      if (message.ok) waiter.resolve(message);
      else waiter.reject(new Error(message.error));
    }
  });
});

async function run() {
  const timings = await ready;
  const readyAt = performance.now();
  const source = "local answer: integer = 42\nreturn answer";
  const check = await request("check", {
    source,
    filename: "chromium-smoke.nupp",
    options: { strict: true, dialect: "lua51" },
  });
  const checkedAt = performance.now();
  const hover = await request("hover", {
    offset: 7,
    options: { dialect: "lua51" },
  });
  const lua51 = await request("compile", {
    source,
    filename: "chromium-smoke.nupp",
    options: { strict: true, optimize: true, dialect: "lua51" },
  });
  const luajit = await request("compile", {
    source: "const value = 2ULL\nreturn value",
    filename: "chromium-luajit.nupp",
    options: { strict: true, dialect: "luajit" },
  });
  if (check.diagnostics.length !== 0 || !hover.found || !lua51.code) {
    throw new Error("Lua 5.1 check, hover, or compile parity failed");
  }
  if (!luajit.code.includes("2ULL") ||
      luajit.diagnostics.some((diagnostic) => diagnostic.code === "NUPP3005")) {
    throw new Error("LuaJIT cross-dialect validation failed");
  }
  const result = {
    ok: true,
    timings: {
      ...timings,
      workerReadyMs: readyAt - started,
      firstCheckMs: checkedAt - readyAt,
      bootAndFirstCheckMs: checkedAt - started,
    },
  };
  output.dataset.status = "passed";
  output.textContent = JSON.stringify(result);
  document.title = "PASS — Nupp Wasm smoke";
}

run().catch(fail);
