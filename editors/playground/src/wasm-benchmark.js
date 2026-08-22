const output = document.querySelector("#result");
const source = "local answer: integer = 42\nreturn answer";

function percentile(values, index) {
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[index];
}

function summary(values) {
  return {
    samples: values,
    medianMs: percentile(values, Math.floor(values.length / 2)),
    slowestMs: Math.max(...values),
  };
}

function sample(workerName, options) {
  return new Promise((resolve, reject) => {
    const started = performance.now();
    const worker = new Worker(new URL(workerName, import.meta.url), { type: "module" });
    let readyAt = 0;
    worker.addEventListener("message", (event) => {
      const message = event.data;
      if (message.type === "boot-error") {
        worker.terminate();
        reject(new Error(message.message));
      } else if (message.type === "ready") {
        readyAt = performance.now();
        worker.postMessage({
          id: 1,
          kind: "check",
          source,
          filename: "timing.nupp",
          options,
        });
      } else if (message.id === 1) {
        const finished = performance.now();
        worker.terminate();
        if (!message.ok) {
          reject(new Error(message.error));
          return;
        }
        resolve({
          bootMs: readyAt - started,
          firstCheckMs: finished - readyAt,
          totalMs: finished - started,
        });
      }
    });
  });
}

async function run() {
  const fengari = [];
  const wasm = [];
  for (let index = 0; index < 3; index += 1) {
    fengari.push(await sample("./worker.js", { strict: true, optimize: true }));
    wasm.push(await sample("./wasm-worker.js", {
      strict: true,
      optimize: true,
      dialect: "lua51",
    }));
  }
  const fengariTotal = summary(fengari.map((entry) => entry.totalMs));
  const wasmTotal = summary(wasm.map((entry) => entry.totalMs));
  const ratio = wasmTotal.medianMs / fengariTotal.medianMs;
  const result = {
    ok: true,
    gatePassed: ratio <= 1.2,
    ratio,
    fengari: { total: fengariTotal, samples: fengari },
    wasm: { total: wasmTotal, samples: wasm },
  };
  output.dataset.status = "complete";
  output.textContent = JSON.stringify(result);
  document.title = `${result.gatePassed ? "PASS" : "BLOCKED"} — Nupp Wasm timing`;
}

run().catch((error) => {
  output.dataset.status = "failed";
  output.textContent = JSON.stringify({ ok: false, error: String(error) });
  document.title = "FAIL — Nupp Wasm timing";
});
