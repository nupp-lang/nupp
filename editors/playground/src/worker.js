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
  runOrThrow(
    `
    local json = require("jsonNative")
    local parser = require("nupp.compiler.parser")
    local check = require("nupp.compiler.check")
    local tree = require("nupp.compiler.lsp.tree")
    local T = require("nupp.compiler.types")
    -- The browser has no filesystem, so its cache cannot persist. Disabling it
    -- also keeps environment startup from reaching the compiler fingerprint's
    -- process-backed directory walk.
    local env = require("nupp.compiler.env").new(".", {cache = false})

    -- Set at the end of a successful __playground_check, read by
    -- __playground_hover. Hover reuses the last check rather than
    -- reparsing/rechecking the whole buffer on every mouse movement — the
    -- same tradeoff a real editor makes reusing its last diagnostics pass
    -- for hover, and one debounced check (see app.js) behind besides.
    local lastResult = nil

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
    -- table walked field-by-field from JS, is what host-runtime.lua's JSON
    -- shim exists for.

    -- The third argument is what the Options panel set, as name=0/1 pairs:
    -- "strict=1,optimize=0". Not JSON, though everything else here crosses as
    -- JSON, because host-runtime.lua's JSON shim implements encode and not
    -- decode -- nothing in the playground had needed to read JSON back until
    -- now, and two booleans do not justify a parser. One argument still, so a
    -- third setting is a field on each side and nothing in between.
    --
    -- No backticks anywhere in this string: it is a JS template literal, and
    -- one would end it early.
    local function settingsOf(options)
        local out = {}
        for name, value in tostring(options or ""):gmatch("([%w_]+)=([01])") do
            out[name] = value == "1"
        end
        return out
    end

    __playground_check = function(source, filename, options)
        local settings = settingsOf(options)
        local result = parser.parse(source, filename)
        local diags
        if #result.errors > 0 then
            diags = result.errors
        else
            local ok, checked = pcall(check.check, result, filename, env,
                {strict = settings.strict == true})
            if not ok then error(checked, 0) end
            diags = checked
            lastResult = result
        end
        return json.encode({diagnostics = diagList(diags)})
    end

    -- What textDocument/hover in nupp.compiler.lsp answers with, minus the parts
    -- (nupp.compiler.lsp.navigate's documentationFor, doc comments) that need a live
    -- LSP session rather than just a checked parse result. offset is a
    -- 1-based byte offset, same as every other position in this codebase.
    __playground_hover = function(offset)
        if not lastResult then return json.encode({found = false}) end
        local tok = tree.tokenAt(lastResult, offset)
        if not tok then return json.encode({found = false}) end
        local def = tok.definition
        -- At a declaration's own name token, inferredType is left as plain
        -- "any" (inference marks usages, not the binding's own name) even
        -- though def.type already holds the real declared signature — the
        -- gap this fixes. At a usage token inferredType is the better
        -- answer, since it can be narrower than the declared type (an "if"
        -- that proved a union down to one branch), so it stays first there.
        local t = tok.inferredType
        if (t == nil or t == T.any) and def and def.type then t = def.type end
        if not t then return json.encode({found = false}) end
        local name = def and def.name or tok.text
        local prefix = def and def.cdef and "cdef "
            or def and def.constant and "const " or ""
        return json.encode({
            found = true,
            name = name,
            signature = prefix .. name .. ": " .. T.tostring(t),
            offset = tok.offset,
            length = #tok.text,
        })
    end

    -- Mirrors nupp.compiler.cli.compile's compile.module, taking source text directly
    -- instead of reading a path off disk.
    __playground_compile = function(source, filename, options)
        local settings = settingsOf(options)
        local result = parser.parse(source, filename)
        if #result.errors > 0 then
            return json.encode({reason = "syntax errors",
                diagnostics = diagList(result.errors)})
        end
        local ok, diags = pcall(check.check, result, filename, env,
            {strict = settings.strict == true})
        if not ok then error(diags, 0) end
        for _, d in ipairs(diags) do
            if d.severity == "error" then
                return json.encode({reason = "type errors", diagnostics = diagList(diags)})
            end
        end
        -- Every pass nupp.compiler.optimize registers runs at level 1, so the Options
        -- panel's one switch is the whole of the distinction there is: -O2 is
        -- accepted by the CLI and reserved for a stronger tier, but selects the
        -- same passes today and would compile byte-identically.
        local optimize = require("nupp.compiler.optimize")
        local okOpt, optErr = pcall(optimize.run, result,
            {level = settings.optimize == true and 1 or 0, filename = filename,
             disabled = {}, relaxed = {}})
        if not okOpt then error(optErr, 0) end
        -- Match build/modules: feature selection follows the tree codegen will
        -- actually emit, so a folded branch cannot keep its runtime installer.
        result.effects = optimize.liveEffects(result)
        local gen = require("nupp.compiler.gen")
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
