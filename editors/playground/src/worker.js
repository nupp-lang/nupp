// Runs the real, self-hosted Nupp compiler (bootstrap/nupp.lua) inside a
// fengari (pure-JS Lua) VM, off the main thread. See ../README.md for why
// this needs a couple of runtime shims rather than running unmodified.
import { lua, lauxlib, lualib, to_luastring } from "fengari";
import hostRuntime from "./host-runtime.lua";
import driver from "./driver.lua";

let L = null;
let ready = false;

function runOrThrow(code, label) {
  const status = lauxlib.luaL_dostring(L, to_luastring(code));
  if (status !== lua.LUA_OK) {
    const msg = lua.lua_tojsstring(L, -1);
    lua.lua_pop(L, 1);
    throw new Error(`${label}: ${msg}`);
  }
}

async function boot() {
  postMessage({ type: "status", message: "starting the Lua VM…" });
  L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  runOrThrow(hostRuntime, "runtime shims");

  postMessage({ type: "status", message: "fetching the compiler…" });
  const res = await fetch(new URL("./nupp-bootstrap.lua", import.meta.url));
  if (!res.ok) throw new Error(`fetching nupp-bootstrap.lua: ${res.status}`);
  // Already browser-safe: build.mjs runs tools/patch-bootstrap-for-browser.lua
  // over bootstrap/nupp.lua at build time — using the bootstrap compiler's own
  // lexer, under real LuaJIT, rather than regexes here — to lower the
  // LuaJIT- and Nupp-only syntax its own implementation uses (not just
  // code it generates for a checked program), and to drop the trailing
  // `os.exit(require("nupp.compiler.cli").main(arg))` full-CLI invocation this
  // playground doesn't need. See that script for what and why.
  const bootstrap = await res.text();

  postMessage({ type: "status", message: "loading the compiler…" });
  runOrThrow(bootstrap, "bootstrap");

  postMessage({ type: "status", message: "warming up the checker…" });
  runOrThrow(driver, "driver");

  ready = true;
  postMessage({ type: "ready" });
}

// `strict=1,optimize=0` — see the settingsOf note in the driver for why this
// is not JSON like everything else crossing this boundary.
function encodeOptions(options) {
  return Object.entries(options || {})
    .map(([key, value]) => `${key}=${value ? 1 : 0}`)
    .join(",");
}

function callForJson(name, source, filename, options) {
  lua.lua_getglobal(L, to_luastring(name));
  lua.lua_pushstring(L, to_luastring(source));
  lua.lua_pushstring(L, to_luastring(filename));
  lua.lua_pushstring(L, to_luastring(encodeOptions(options)));
  const rc = lua.lua_pcall(L, 3, 1, 0);
  const text = lua.lua_tojsstring(L, -1);
  lua.lua_pop(L, 1);
  if (rc !== lua.LUA_OK) throw new Error(text);
  return JSON.parse(text);
}

function hoverAt(offset) {
  lua.lua_getglobal(L, to_luastring("__playground_hover"));
  lua.lua_pushinteger(L, offset);
  const rc = lua.lua_pcall(L, 1, 1, 0);
  const text = lua.lua_tojsstring(L, -1);
  lua.lua_pop(L, 1);
  if (rc !== lua.LUA_OK) throw new Error(text);
  return JSON.parse(text);
}

const FFI_MESSAGE_HINT = "no native C ABI to introspect";

function friendlyError(err) {
  const msg = String(err && err.message ? err.message : err);
  if (msg.includes(FFI_MESSAGE_HINT)) {
    return "This program reaches into real C struct/FFI layout (struct, " +
      "cdef, import-c), which needs LuaJIT's actual C ABI. That isn't " +
      "available in the browser playground — see the README for why.";
  }
  return msg;
}

self.onmessage = (event) => {
  const { id, kind, source, filename, offset, options } = event.data;
  if (!ready) {
    postMessage({ id, ok: false, error: "the compiler is still loading" });
    return;
  }
  try {
    if (kind === "check") {
      postMessage({ id, ok: true, ...callForJson("__playground_check", source, filename || "playground.nupp", options) });
    } else if (kind === "compile") {
      postMessage({ id, ok: true, ...callForJson("__playground_compile", source, filename || "playground.nupp", options) });
    } else if (kind === "hover") {
      postMessage({ id, ok: true, ...hoverAt(offset) });
    } else {
      postMessage({ id, ok: false, error: `unknown request kind "${kind}"` });
    }
  } catch (err) {
    postMessage({ id, ok: false, error: friendlyError(err) });
  }
};

// Firefox's Error#stack is frame lines only ("fn@url:line:col"), with no
// leading "Name: message" the way V8's is — so showing just `.stack` (the
// previous version of this file) silently drops the actual reason there.
// Always lead with `.message`.
function describeError(err) {
  if (!(err instanceof Error)) return String(err);
  return err.stack && err.stack.includes(err.message)
    ? err.stack
    : `${err.message}\n${err.stack || ""}`;
}

boot().catch((err) => {
  postMessage({ type: "boot-error", message: describeError(err) });
});
