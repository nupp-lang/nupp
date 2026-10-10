// Runs one contract scenario through the packaged entry, as a page would: the
// application in its Worker, some kinds answered by a module loaded into that
// Worker (relay-worker.mjs) and the rest on this page, relayed by the Worker.
import {testHost} from "./handlers.mjs";

const out = document.querySelector("#result");
const query = new URL(location.href).searchParams;
const name = query.get("name") || "arity";

try {
  const application = await import("./app/nupp-browser-app.mjs");
  const {host, state} = testHost();
  // The Worker module answers echo and the stream kinds; everything else stays here.
  const workerKinds = new Set(["test.echo", "test.results", "test.pushInput", "test.packet", "test.log",
    "test.block", "test.outbound"]);
  const pageHandlers = Object.fromEntries(Object.entries(host.handlers).filter(([kind]) => !workerKinds.has(kind)));
  pageHandlers["bench.program"] = () => ["scenarios.lua", name, "{}"];
  let ended = 0;
  const result = await application.run({
    host: {
      handlers: pageHandlers,
      module: new URL("./relay-worker.mjs", location.href),
      end: () => { ended++; },
    },
  });
  out.textContent = JSON.stringify({ok: true, outcome: result, host: {live: state.live.size, ended}});
  out.dataset.status = "passed";
} catch (error) {
  out.textContent = JSON.stringify({ok: false, error: String(error), stack: error.stack});
  out.dataset.status = "failed";
}
