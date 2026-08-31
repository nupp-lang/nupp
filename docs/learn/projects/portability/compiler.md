---
order: 515
---

# Portable compiler bundle

The portable compiler bundle runs Nupp checking, lowering, optimization, and
hover queries inside a stock Lua 5.1 host. Build it when an application needs
the compiler without giving that host LuaJIT, a filesystem, or native modules.

```bash
scripts/prelude-image
lua5.1 build/playground/nupp-compiler.lua
```

`scripts/prelude-image` rather than `nupp build --target playgroundCompiler`:
the bundle carries a serialized prelude graph that is generated from the
compiler, so building it takes two passes. `NUPP_PRELUDE_LUA` names the
interpreter to generate under, which defaults to the pinned LuaJIT.

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

The portable entry also carries a checked image of the standard prelude's type
graph. A fresh graph is hydrated when each dialect environment is first used.
The image is inert data rather than Lua source, and the hydrator is an ordinary
checked Nupp module. The acceptance test reconstructs the graph from the
declaration source and requires both the generated image and a hydrated round
trip to reproduce the tracked bytes exactly.

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

## Browser host

The playground runs the same tested bundle inside official Lua 5.1 compiled to
WebAssembly. Its generated assets are:

- `nupp-playground.mjs`, the ES module loader;
- `nupp-playground.wasm`, the Lua VM and host ABI;
- `nupp-compiler-<digest>.lua`, the content-addressed compiler; and
- `nupp-playground-assets.json`, which names the three artifacts and records
  their sizes and full compiler digest.

The Worker fetches the compiler separately from the VM. The C host computes
SHA-256 over those exact bytes and compares it with the digest compiled into
the Wasm module before passing them to `luaL_loadbuffer`. A mismatch fails
closed. The host has no Emscripten virtual filesystem.

The byte interface accepts one compiler bundle at boot and JSON requests after
that:

```c
int32_t nupp_boot(const uint8_t *bundle, uint32_t length);
uint32_t nupp_request(const uint8_t *data, uint32_t length);
const uint8_t *nupp_response_data(uint32_t handle);
uint32_t nupp_response_size(uint32_t handle);
void nupp_response_free(uint32_t handle);
const char *nupp_last_error(void);
const char *nupp_bundle_sha256(void);
```

Responses remain owned by the host until `nupp_response_free`. The Worker
copies a response before freeing its handle and frees request and bundle
allocations on both success and failure.

Keeping the VM and compiler separate lets a compiler-only release reuse the
cached Wasm module, while a host-only release can reuse a content-addressed
compiler asset. The filename is a cache key; SHA-256 verification is the
integrity check.

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
[build.md](../build.md#target-source-sets) for the source-set contract and
[portable-libraries.md](libraries.md) for dependencies that supply
runtime seams.
