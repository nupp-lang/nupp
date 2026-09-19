# Portable Lua libraries

Nupp libraries normally use LuaJIT on both native and browser hosts. Stock Lua
5.1 exports use the checked compatibility profile below.

## Lua 5.1 source compatibility

`compat = "lua51"` checks a project against a stock Lua 5.1 source and runtime
subset while retaining ordinary LuaJIT emission. Set it at the manifest root:

```lua
return {
   compat = "lua51",
   include = {"src"},
}
```

For a one-off check or build, use `nupp check --compat lua51` or
`nupp build --compat lua51`. Targets and individual files cannot disable an
inherited requirement. Combining compatibility with a legacy `dialect` is an
error. JSON check/build reports include the resolved `compat` value.

Types, generics and other erased declarations remain available. Ordinary
functions, tables, module exports, varargs, coroutines and non-suspending cleanup
can qualify. Checks run before optimization, including unreachable source, and
also validate generated Lua. Imports need checked runtime source; declaration
files do not certify unseen implementations. Literal `loadstring` source is
checked without execution. Dynamic module names and opaque code loading fail.

Compatibility keeps provenance through local aliases and casts. Passing runtime
namespace tables or code loaders through containers or unchecked callbacks is
rejected because their use can no longer be verified. Registry, upvalue and
local-variable reflection likewise cannot certify runtime dependencies.

This is narrower than `dialect = "lua51"`. Runtime `const`, compound assignment,
bit operators, `continue`, jumps, short functions, safe navigation, extended
literals, FFI, native `bit`, `string.buffer`, exact-width representations and VM
table helpers are rejected. There are no automatic bit, integer or struct
provider substitutions. An explicit pure-Lua bit or integer library can qualify
through the same checks as other source dependencies. A provider's internal
repository API does not become a public dependency API through this flag.

Stock Lua 5.1 cannot yield through protected calls. Cleanup whose expanded
runtime dependencies reach `runtime.suspension` fails even if that particular
body does not yield. Variadic cleanup and extra `xpcall` arguments also fail.
The ordinary closure cleanup implementation is used when the optimization
requiring LuaJIT's extra `xpcall` arguments is unavailable.

The guarantee concerns emitted syntax and checked runtime requirements, not
identical behavior across every VM or operating system. Platform services still
need their own supported host. The legacy dialects remain available during the
browser migration; they keep their existing lowering behavior.

## Legacy lowering targets

The legacy targets remain available during the browser rollback release. Their
provider substitutions are separate from the source compatibility guarantee.

A library can target LuaJIT's native representations or portable Lua syntax. The
target determines representations and calling conventions. Runtime service
providers supply operations for those representations.

```lua
return {
   include = {"src"},
   build = {
      default = "portable",
      targets = {
         native = {entries = {"main"}, dialect = "luajit", outDir = "build/luajit"},
         portable = {entries = {"main"}, dialect = "lua51", outDir = "build/lua51"},
      },
   },
}
```

Check and build each supported target:

```bash
nupp check --target native
nupp check --target portable
nupp build --target native
nupp build --target portable
```

## Target representations

`luajit` uses native FFI pointers, layouts, integer values, and supported operators.
`luajit-compat` keeps those representations while lowering syntax for older
embedded LuaJIT parsers. `lua51` lowers portable operations to retained module
functions. Provider names do not change generated operations or machine layouts.

Portable bit operations and table struct values have built-in implementations.
Physical storage requires a compatible implementation at module initialization.
The Wasm storage implementation supplies its exact integers, reference-valued
structs, and memory host together. A module requiring physical storage fails to
load if that representation is unavailable.

Unsupported source operations still fail during checking. Foreign C calls need a
LuaJIT target and a compatible library. Browser calls execute against the i386
guest's libraries; registering a provider cannot change that requirement.

## LuaJIT modules

`require("ffi")`, `require("string.buffer")`, `require("table.new")` and the
`jit.*` modules are LuaJIT's, and the `lua51` dialect refuses them: each does
something a portable target cannot do at all, or can only do in part. Reach
them through an adapter instead, the way [](nupp.text) covers buffers with one
`Buffer` type over both implementations.

`bit` is the exception, and the only one. Every name BitOp declares has a scalar
implementation with the same signature, so `require("bit")` resolves on every
dialect: a LuaJIT target loads the C library and a portable target loads the
scalar implementation beneath it.

```nupp
const bit = require("bit")

print(bit.tohex(bit.bswap(0x11223344))) -- 44332211
```

Write `&`, `|`, `~`, `<<`, `>>` and `~>>` where an operator says it, since the
compiler lowers each one per target and nothing has to name an implementation.
Require the module for `tohex`, `bswap`, `rol`, `ror` and `tobit`, which have no
operator. The bare `bit` global stays LuaJIT's: a global cannot be supplied
without writing to `_G`, so portable source requires the module.

## Require-time selection

SPI covers operations whose implementation varies. Fixed hashing, scalar SIMD,
layout arithmetic, and other ordinary helpers are normal modules.

Implementation interfaces live beside their consuming library in `.spi` modules.
Importing a declaration loads no implementation. Packages advertise their modules
in `nupp/spi.json`; `nupp.spi.load(Interface)` lazily iterates them in dependency
order. The consumer decides what wins.

Standard-library facades choose the unique highest `priority`, with an omitted
priority counting as zero. A highest-priority tie fails initialization. Empty
discovery uses the facade's explicit target-dependent fallback. Each facade binds
its actual operations during module initialization, so calls perform no SPI lookup.

## Runtime interfaces

[SPI](../spi.md#standard-library-providers) lists each interface and its owning
module. Shared storage, struct, memory-host, and integer declarations remain in
`nupp.runtime.representation.spi`; storage and its integer operations must agree.

`nupp.text` owns the portable buffer surface and one shared `Buffer` type.
Its native adapter uses LuaJIT's `string.buffer`. Explicitly native pointer and
serialization facilities remain on the native `string.buffer` surface.

GPU providers use the shared interfaces in `nupp.gpu.spi`. Each context retains its
device methods. CPU workgroups and tensor layout operations are ordinary code.
HTTP clients are created with `nupp.io.http.client(options)` and retain their
response and body cleanup responsibilities.

Host code pumps network events with `nupp.io.net.pump(milliseconds)`. Process
providers construct exit values with `nupp.io.process.types.exited`.

## Dependency providers

A runtime dependency lists qualified interface names and implementation modules
in `nupp/spi.json`. The build checks ordinary assignment compatibility, including
generic signatures, ownership, and suspension. Lua implementations need a matching
`.d.nupp` declaration or typed adapter. Discovery never executes provider code.

Only target runtime dependencies contribute implementations. Built-in native adapters are
excluded from portable payloads. See [SPI](../spi.md) for metadata and examples.

## Workers

Worker lanes start fresh Lua states with the artifact's immutable provider index.
They load and cache their own module instances. Provider objects and closures do
not cross lane boundaries; each consumer chooses during its own initialization.

## Validation

Type-check provider exports and run behavioral conformance tests on each supported
host. Exercise signed bit operations, JSON markers, buffer ownership, storage
interoperability, and resource lifecycles. Tests using different selections should
initialize separate states. Instrument resolution during module loading and verify
that repeated exported operations leave that count unchanged.
