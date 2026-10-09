// Runs one host channel program in the real LuaJIT browser guest. The query
// names it: `file` (scenarios.lua or bench.lua), `name`, and `options`, a JSON
// object handed to the program.
import {testHost} from "./handlers.mjs";

const out = document.querySelector("#result");
const query = new URL(location.href).searchParams;
const file = query.get("file") || "scenarios.lua";
const name = query.get("name") || "arity";
const options = JSON.parse(query.get("options") || "{}");

function luaLiteral(value) {
  if (value === null || value === undefined) return "nil";
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  if (Array.isArray(value)) return `{${value.map(luaLiteral).join(",")}}`;
  return `{${Object.entries(value).map(([key, item]) => `[${JSON.stringify(key)}]=${luaLiteral(item)}`).join(",")}}`;
}

try {
  const {runPackagedNuppLuaJITApp} = await import("./app/app-runtime.mjs");
  const {host, state} = testHost();
  const initialize = new TextEncoder().encode(
    `__hostChannelProgram = {file = ${luaLiteral(file)}, name = ${luaLiteral(name)}, options = ${luaLiteral(options)}}`,
  );
  const started = performance.now();
  const outcome = await runPackagedNuppLuaJITApp(new URL("./app/nupp-browser-app.json", location.href).href,
    {host, initialize});
  out.textContent = JSON.stringify({
    ok: outcome?.ok === true,
    outcome,
    elapsedMs: performance.now() - started,
    host: {live: state.live.size, released: state.released.length, ended: state.ended, packets: state.packets.length},
  });
  out.dataset.status = "passed";
} catch (error) {
  out.textContent = JSON.stringify({ok: false, error: String(error), stack: error.stack});
  out.dataset.status = "failed";
}
