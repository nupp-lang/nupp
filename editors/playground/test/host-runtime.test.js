import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { lauxlib, lua, lualib, to_luastring } from "fengari";

const hostRuntime = readFileSync(new URL("../src/host-runtime.lua", import.meta.url), "utf8");
const driver = readFileSync(new URL("../src/driver.lua", import.meta.url), "utf8");
const bootstrap = readFileSync(new URL("../dist/nupp-bootstrap.lua", import.meta.url), "utf8");

function run(L, source) {
  const status = lauxlib.luaL_dostring(L, to_luastring(source));
  const message = status === lua.LUA_OK ? null : lua.lua_tojsstring(L, -1);
  if (status !== lua.LUA_OK) lua.lua_pop(L, 1);
  assert.equal(status, lua.LUA_OK, message);
}

// The `loadstring` shim rewrites LuaJIT-only syntax out of a chunk this VM
// refuses, so that nupp.compiler.gen's re-load of the code it just generated —
// the NUPP3005 "generated code does not load" check, which reads the host's
// parser as if it were the target's — answers for LuaJIT rather than for
// fengari. It asks the compiler's own lexer which tokens are which; this
// stands in for that lexer with the same contract (`kind` is "name" for an
// identifier, the keyword's own text for a keyword, "number" for a numeral,
// and a string literal's contents are never re-tokenized), the contract
// tools/patch-bootstrap-for-browser.lua relies on for real at build time.
const STUB_LEXER = `
package.preload["nupp.compiler.lexer"] = function()
    local keywords = {}
    for word in ("and break do else elseif end false for function goto if in "
        .. "local nil not or repeat return then true until while"):gmatch("%S+") do
        keywords[word] = true
    end
    return {lex = function(source)
        local tokens, position = {}, 1
        local function emit(text, offset, kind)
            tokens[#tokens + 1] = {text = text, offset = offset, kind = kind}
        end
        while position <= #source do
            local char = source:sub(position, position)
            if char == '"' or char == "'" then
                local closing = (source:find(char, position + 1, true) or #source) + 1
                emit(source:sub(position, closing - 1), position, "string")
                position = closing
            elseif char:match("[%w_]") then
                local first, last = source:find("[%w_]+", position)
                local text = source:sub(first, last)
                emit(text, first, keywords[text] or (text:match("^%d") and "number" or "name"))
                position = last + 1
            elseif char:match("%s") then
                position = position + 1
            else
                -- Punctuation is a token too, and the rewrite depends on it:
                -- the field access in "held.const, X" is only distinguishable
                -- from a declaration by the comma between them. (No backticks
                -- in this string: it is a JS template literal.)
                emit(char, position, char)
                position = position + 1
            end
        end
        return tokens, {}
    end}
end
`;

function withStubLexer(source) {
  return `${STUB_LEXER}\n${source}`;
}

test("loads generated code that declares LuaJIT constants", () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  run(L, hostRuntime);
  run(L, withStubLexer([
    'local chunk = assert(loadstring("const X = 41\\nreturn X + 1", "@generated.lua"))',
    "assert(chunk() == 42)",
    'assert(assert(loadstring("const N = 0xFFULL\\nreturn N"))() == 255)',
    'assert(assert(loadstring("const function f() return 7 end\\nreturn f()"))() == 7)',
  ].join("\n")));
  lua.lua_close(L);
});

test("rewrites only real const declarations, never a name or string that reads like one", () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  run(L, hostRuntime);
  // `const` is a soft keyword: a field named `const`, and the five characters
  // inside a string of generated-code text, are not declarations. Both sit in
  // the same chunk as a real one, so the rewrite does run over them.
  run(L, withStubLexer(`
    local source = table.concat({
      "const X = 1",
      "local held = {const = 5}",
      "if held.const and true then return held.const, X, 'const A' end",
    }, "\\n")
    local first, second, third = assert(loadstring(source))()
    assert(first == 5 and second == 1)
    assert(third == "const A")
  `));
  lua.lua_close(L);
});

test("still refuses generated code that is malformed for its own reasons", () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  run(L, hostRuntime);
  run(L, withStubLexer([
    // What NUPP3005 exists to catch has to survive the rewrite: this chunk
    // is unparseable with or without the const, and the reported reason is
    // the one that remains after the dialect gap closes.
    'local chunk, reason = loadstring("const X = 1\\nreturn +", "@generated.lua")',
    "assert(chunk == nil)",
    'assert(reason:find("unexpected symbol") ~= nil, reason)',
    // With no compiler loaded there is nothing to rewrite from, and the
    // original refusal stands rather than a confusing second one.
    "package.preload[\"nupp.compiler.lexer\"] = nil",
    "package.loaded[\"nupp.compiler.lexer\"] = nil",
    'assert(loadstring("const X = 1\\nreturn X") == nil)',
  ].join("\n")));
  lua.lua_close(L);
});

test("keeps loadstring's plain-Lua job for the constant folder", () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  run(L, hostRuntime);
  run(L, [
    'assert(assert(loadstring("return 1 + 2"))() == 3)',
    'assert(loadstring("return 1 +") == nil)',
  ].join("\n"));
  lua.lua_close(L);
});

test("provides LuaJIT's global unpack compatibility helper", () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  run(L, hostRuntime);
  run(L, [
    "local args = {n = 2, 10, 20}",
    "local ok, value = pcall(function(a, b) return a + b end, unpack(args, 1, args.n))",
    "assert(ok and value == 30)",
  ].join("\n"));
  lua.lua_close(L);
});

test("does not expose native environment variables", () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  run(L, hostRuntime);
  run(L, 'assert(os.getenv("NUPP_COMPILER_ROOT") == nil)');
  lua.lua_close(L);
});

test("provides an empty filesystem without loading the native ABI", () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  run(L, hostRuntime);
  run(L, [
    'assert(require("nupp.io.files") == nupp.io.files)',
    "assert(#nupp.io.files.list('.') == 0)",
    "assert(nupp.io.files.info('nupp.lua') == nil)",
    "assert(nupp.io.files.isDirectory('.') == false)",
    "assert(nupp.io.files.pendingTransfers() == 0)",
  ].join("\n"));
  lua.lua_close(L);
});

test("provides the fixed-width word arena used by the compiler lexer", () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  run(L, hostRuntime);
  run(L, [
    'local ffi = require("ffi")',
    'local source = ffi.new("uint32_t[?]", 2)',
    "source[0], source[1] = 17, 29",
    'local target = ffi.new("uint32_t[?]", 4)',
    "assert(target[0] == 0 and target[3] == 0)",
    "ffi.copy(target, source, 8)",
    "assert(target[0] == 17 and target[1] == 29 and target[2] == 0)",
    'assert(not pcall(ffi.new, "char[1]"))',
    "assert(not pcall(ffi.copy, target, source, 12))",
  ].join("\n"));
  lua.lua_close(L);
});

test("boots the real compiler driver and checks the calls documentation example", () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  run(L, hostRuntime);
  run(L, bootstrap);
  run(L, driver);
  run(L, `
    local docSyntax = require("nupp.compiler.doc.syntax")
    local ticks = string.rep(string.char(96), 3)
    local prefix, fence, options = docSyntax.markdownFence:match(" " .. ticks .. "nupp:playground")
    assert(prefix == " " and fence == ticks and options == "nupp:playground")
    assert(docSyntax.lineNumber:match("nupp:line-numbers=7") == "7")

    local luaFormat = require("nupp.compiler.luaformat")
    local parsed, why = luaFormat.analyze("%-+#09.2f %q %% %d %?")
    assert(why == nil, why)
    assert(parsed.format == "%-+#09.2f %q %% %d %s", parsed.format)
    assert(parsed.debugArguments[1] == false and parsed.debugArguments[4] == true)
    local missing, invalid = luaFormat.analyze("%..f")
    assert(missing == nil and invalid ==
      'invalid string.format directive starting at "%..f"', tostring(invalid))

    local source = [=[
local record Vec3
    x: number
    y: number
    z: number
end

local function draw(x: number, y: number, color: string?): nil
    print(x, y, color)
end

local function render(position: Vec3): nil
    draw({x, y} = position, color = "blue")
end
]=]
    local response = __playground_check(source, "playground.nupp", "strict=1,optimize=0")
    assert(response:find('"diagnostics"', 1, true), response)
    assert(not response:find('"severity":"error"', 1, true), response)
    local compiled = __playground_compile(source, "playground.nupp", "strict=1,optimize=0")
    assert(compiled:find('"code"', 1, true), compiled)
    assert(not compiled:find('"reason"', 1, true), compiled)
  `);
  lua.lua_close(L);
});

test("wraps LuaJIT bit values without overflowing Fengari hex integers", () => {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  run(L, hostRuntime);
  run(L, [
    "assert(bit.tobit(4294967295) == -1)",
    "assert(bit.tobit(2147483648) == -2147483648)",
    "assert(bit.bnot(0) == -1)",
    'assert(bit.tohex(-1) == "ffffffff")',
  ].join("\n"));
  lua.lua_close(L);
});
