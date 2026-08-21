---
order: 515
---

# Portable compiler bundle

The portable compiler bundle runs Nupp checking, lowering, optimization, and
hover queries inside a stock Lua 5.1 host. Build it when an application needs
the compiler without giving that host LuaJIT, a filesystem, or native modules.

```bash
nupp build --target playgroundCompiler
lua5.1 build/playground/nupp-compiler.lua
```

The bundle returns its API instead of starting the command-line interface, so
an embedding host normally loads it as a chunk:

```lua
local chunk = assert(loadfile("build/playground/nupp-compiler.lua"))
local Browser = chunk()
local session = Browser.new()

local result = session:check(
   "local answer: integer = 42\nreturn answer",
   "example.nupp",
   {strict = true, dialect = "lua51"}
)
```

## Host libraries

The compiler needs the base, package, table, string, math, and coroutine
libraries. It does not open libraries itself, inspect the filesystem, start a
process, or load a native Lua module.

The bundle carries its checked table trivia arena, scalar bit operations, and
pinned lunajson adapter as real modules. The LuaJIT compiler entry selects the
FFI arena directly, while this entry selects the table arena once before the
lexer creates a record. Neither path tests the host dialect per token.

## Session methods

One session owns a lazy checker environment for each output dialect. The
default dialect is `lua51`:

```lua
local checked = session:check(source, "example.nupp", {
   strict = true,
   dialect = "lua51"
})

local compiled = session:compile(source, "example.nupp", {
   strict = true,
   optimize = true,
   dialect = "luajit"
})

local hover = session:hover(12)
```

`check` returns normalized diagnostics. `compile` returns those diagnostics
and either `code` or a refusal `reason`. `hover` reads the last successful
result for the most recently selected dialect.

`request` is the JSON boundary for a Worker or another byte-oriented host. It
accepts the same request fields and returns one JSON response:

```lua
local response = session:request([[
{"kind":"check","source":"return 1","options":{"dialect":"lua51"}}
]])
```

Use the structured methods inside Lua. The JSON method exists for a host ABI,
not as a second compiler API.

## Output dialects

A stock Lua 5.1 host can produce both Lua 5.1 and LuaJIT source. Generated
source is parsed by the host only when its target dialect matches the host
dialect. The LuaJIT result is instead parsed by LuaJIT in the differential
test suite, so LuaJIT-only `const` declarations and `ULL` literals do not
produce a false generation diagnostic from Lua 5.1.

The session resolves dialects, capabilities, standard modules, and selected
backends through the same compiler machinery as `nupp check`. Browser sessions
then mark `cinterop` and `cstorage` unavailable because their in-memory host
has no native layout or storage provider.

## Limits

The portable entry accepts one in-memory source file. It does not resolve a
project, read imported application files, run comptime worker processes,
render documentation, import C headers, or perform AOT compilation.

The bundle contains the standard-library declaration resources used while
checking source. A module required through a computed name is available only
when the bundle target selected it independently. See
[build.md](build.md#target-source-sets) for the source-set contract and
[portable-libraries.md](portable-libraries.md) for dependencies that supply
runtime seams.
