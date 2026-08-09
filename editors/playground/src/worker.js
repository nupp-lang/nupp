// Runs the real, self-hosted Nupp compiler (bootstrap/nupp.lua) inside a
// fengari (pure-JS Lua) VM, off the main thread. See ../README.md for why
// this needs a couple of runtime shims rather than running unmodified.
import { lua, lauxlib, lualib, to_luastring } from "fengari";
import hostRuntime from "./host-runtime.lua";

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
  let bootstrap = await res.text();

  // nupp.build.hash uses LuaJIT's 64-bit cdata integer literal syntax
  // (0x...ULL) for an xxhash implementation used only by incremental build
  // caching, which this playground never exercises. Standard Lua 5.3+ has
  // native 64-bit integers, so the same hex digits parse fine once the
  // LuaJIT-only suffix is stripped — only the parse needs to succeed, the
  // build cache is never actually reached.
  bootstrap = bootstrap.replace(/\b(0[xX][0-9A-Fa-f]+|[0-9]+)U?LL\b/g, "$1");

  // The file ends by running the full CLI
  // (os.exit(require("nupp.cli").main(arg))), which eagerly requires every
  // subcommand — including ones this playground never calls and that pull in
  // more than the checker needs. The driver below requires only what
  // checking and compiling a buffer actually touch.
  const trailer = 'os . exit ( require ( "nupp.cli" ) . main ( arg ) )';
  if (!bootstrap.includes(trailer)) {
    throw new Error("bootstrap/nupp.lua's trailing CLI call has changed shape");
  }
  bootstrap = bootstrap.replace(trailer, "");

  postMessage({ type: "status", message: "loading the compiler…" });
  runOrThrow(bootstrap, "bootstrap");

  postMessage({ type: "status", message: "warming up the checker…" });
  runOrThrow(
    `
    local json = require("cjson")
    local parser = require("nupp.parser")
    local check = require("nupp.check")
    local env = require("nupp.env").new(".")

    local function diagList(diags)
        local out = {}
        for i, d in ipairs(diags) do
            out[i] = {
                code = d.code, msg = d.msg, severity = d.severity,
                line = d.line, col = d.col, offset = d.offset, length = d.length,
                help = d.help, notes = d.notes, related = d.related,
            }
        end
        return out
    end

    -- Every entry point below returns one JSON string: {diagnostics=...}
    -- for a check, {code=..., reason=..., diagnostics=...} for a compile.
    -- Crossing the JS boundary as one encoded string, rather than a raw Lua
    -- table walked field-by-field from JS, is what host-runtime.lua's cjson
    -- shim exists for.

    __playground_check = function(source, filename)
        local result = parser.parse(source, filename)
        local diags
        if #result.errors > 0 then
            diags = result.errors
        else
            local ok, checked = pcall(check.check, result, filename, env, {strict = false})
            if not ok then error(checked, 0) end
            diags = checked
        end
        return json.encode({diagnostics = diagList(diags)})
    end

    -- Mirrors nupp.cli.compile's compile.module, taking source text directly
    -- instead of reading a path off disk.
    __playground_compile = function(source, filename)
        local result = parser.parse(source, filename)
        if #result.errors > 0 then
            return json.encode({reason = "syntax errors",
                diagnostics = diagList(result.errors)})
        end
        local ok, diags = pcall(check.check, result, filename, env, {strict = false})
        if not ok then error(diags, 0) end
        for _, d in ipairs(diags) do
            if d.severity == "error" then
                return json.encode({reason = "type errors", diagnostics = diagList(diags)})
            end
        end
        local okOpt, optErr = pcall(require("nupp.optimize").run, result,
            {level = 0, filename = filename, disabled = {}, relaxed = {}})
        if not okOpt then error(optErr, 0) end
        local gen = require("nupp.gen")
        local okGen, code, genDiags = pcall(gen.generate, result, filename)
        if not okGen then error(code, 0) end
        if genDiags and #genDiags > 0 then
            return json.encode({reason = "code generation errors",
                diagnostics = diagList(genDiags)})
        end
        return json.encode({code = code, diagnostics = diagList(diags)})
    end
    `,
    "driver"
  );

  ready = true;
  postMessage({ type: "ready" });
}

function callForJson(name, source, filename) {
  lua.lua_getglobal(L, to_luastring(name));
  lua.lua_pushstring(L, to_luastring(source));
  lua.lua_pushstring(L, to_luastring(filename));
  const rc = lua.lua_pcall(L, 2, 1, 0);
  const text = lua.lua_tojsstring(L, -1);
  lua.lua_pop(L, 1);
  if (rc !== lua.LUA_OK) throw new Error(text);
  return JSON.parse(text);
}

const FFI_MESSAGE_HINT = "not available in the browser playground";

function friendlyError(err) {
  const msg = String(err && err.message ? err.message : err);
  if (msg.includes(FFI_MESSAGE_HINT)) {
    return "This program reaches into real C struct/FFI layout (records, " +
      "cdef, import-c), which needs LuaJIT's actual C ABI. That isn't " +
      "available in the browser playground — see the README for why.";
  }
  return msg;
}

self.onmessage = (event) => {
  const { id, kind, source, filename } = event.data;
  if (!ready) {
    postMessage({ id, ok: false, error: "the compiler is still loading" });
    return;
  }
  try {
    if (kind === "check") {
      postMessage({ id, ok: true, ...callForJson("__playground_check", source, filename || "playground.nupp") });
    } else if (kind === "compile") {
      postMessage({ id, ok: true, ...callForJson("__playground_compile", source, filename || "playground.nupp") });
    } else {
      postMessage({ id, ok: false, error: `unknown request kind "${kind}"` });
    }
  } catch (err) {
    postMessage({ id, ok: false, error: friendlyError(err) });
  }
};

boot().catch((err) => {
  postMessage({ type: "boot-error", message: String(err && err.stack ? err.stack : err) });
});
