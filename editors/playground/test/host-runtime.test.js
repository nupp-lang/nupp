import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { lauxlib, lua, lualib, to_luastring } from "fengari";

const hostRuntime = readFileSync(new URL("../src/host-runtime.lua", import.meta.url), "utf8");

function run(L, source) {
  const status = lauxlib.luaL_dostring(L, to_luastring(source));
  const message = status === lua.LUA_OK ? null : lua.lua_tojsstring(L, -1);
  if (status !== lua.LUA_OK) lua.lua_pop(L, 1);
  assert.equal(status, lua.LUA_OK, message);
}

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
