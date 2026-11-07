import {createPortChannel} from "../../../../../runtime/wasm/channel.mjs";

const result = document.querySelector("#result");
const workers = [];
async function run() {
  const {sender, receiver} = createPortChannel(4, 16);
  const total = 1024;
  const reports = [];
  const ready = [];
  for (const endpoint of [sender, receiver]) {
    const worker = new Worker(new URL("./channel-route-worker.mjs", import.meta.url), {type: "module"});
    workers.push(worker);
    let becameReady;
    ready.push(new Promise(resolve => becameReady = resolve));
    reports.push(new Promise((resolve, reject) => {
      worker.addEventListener("error", event => reject(new Error(event.message)));
      worker.addEventListener("message", event => {
        if (event.data.type === "ready") becameReady();
        else if (event.data.type === "finished") resolve(event.data);
        else if (event.data.type === "failed") reject(new Error(event.data.error));
      });
    }));
    const snapshot = endpoint.move();
    worker.postMessage({type: "setup", endpoint: snapshot, total}, [snapshot.port]);
  }
  await Promise.all(ready);
  const blockedAt = Date.now();
  for (const worker of workers) worker.postMessage({type: "go"});
  // Both guests must exchange more packets than their bounded buffer can hold
  // while this page is unavailable to relay data or return credits.
  while (Date.now() - blockedAt < 1000) {}
  const resumedAt = Date.now();
  const completed = await Promise.all(reports);
  const consumed = completed.find(report => report.role === "receiver");
  if (consumed.count !== total || consumed.finishedAt < blockedAt || consumed.finishedAt >= resumedAt) {
    throw new Error("workers did not complete direct bounded delivery during the page stall");
  }
  return {ok: true, packets: total, messageLimit: 4, byteLimit: 16,
    pageStallMs: resumedAt - blockedAt, completedDuringStall: true};
}
run().then(value => {
  result.dataset.status = "passed";
  result.textContent = JSON.stringify(value);
}, error => {
  result.dataset.status = "failed";
  result.textContent = JSON.stringify({ok: false, error: String(error.stack || error)});
}).finally(() => {
  for (const worker of workers) worker.terminate();
});
