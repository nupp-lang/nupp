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
inherited requirement. JSON check/build reports include the resolved `compat` value.

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

Use `_G.assert` for stock assertions. The public `assert` facade includes
test-suite state and reflection outside this profile.

```nupp
local assert = _G.assert
local value: string = assert("ready")
return value
```

Runtime `const`, compound assignment,
bit operators, `continue`, jumps, short functions, safe navigation, extended
literals, FFI, native `bit`, exact-width representations and VM
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
need their own supported host. Nupp emits LuaJIT code only; compatibility is a
source contract, not a second lowering backend.

Unsupported source operations still fail during checking. Foreign C calls need a
LuaJIT target and a compatible library. Browser calls execute against the i386
guest's libraries; registering a provider cannot change that requirement.

## LuaJIT modules

`require("ffi")`, `require("table.new")`, `bit`, and
the `jit.*` modules are LuaJIT facilities, so the compatibility profile rejects
them. Use an ordinary pure-Lua dependency when stock Lua 5.1 support is required.

```nupp
print(bit.tohex(bit.bswap(0x11223344))) -- 44332211
```

The compatibility profile rejects bit operators as well. A checked pure-Lua
library can expose equivalent operations explicitly.

## Target implementations

The build binds builtin implementations for the selected native or browser
host. Standard-library calls use those bindings; package descriptors do not
replace them. Fixed hashing, scalar SIMD, and layout arithmetic remain ordinary
modules.

Storage and struct operations use private runtime contracts. Their layouts and
scalar codecs agree with the representation compiled into the program.
[](io.Buffer) owns growable FIFO byte storage on native and browser hosts.
Borrowed spans retain its storage for the duration of their loan. Serialization
belongs to [](serde).

Each GPU context retains its device methods. CPU workgroups and tensor layout
operations are ordinary code. HTTP clients are created with
`io.http.Client.create(options)` and retain their response and body cleanup
responsibilities.

Host code pumps network events with `io.net.pump(milliseconds)`. Processes
return plain `io.Process.Exit` data containing `exitcode`, `killed`, and
`timedout`.

## Dependency providers

A runtime dependency lists its own qualified interface names and implementation
modules in `nupp/spi.json`. The build checks ordinary assignment compatibility,
including generic signatures, ownership, and suspension. Lua implementations
need a matching `.d.nupp` declaration or typed adapter. Discovery never executes
provider code.

Only target runtime dependencies contribute implementations. The selected host
determines which builtin adapters the build includes. See [SPI](../spi.md) for
metadata and examples.

## Workers

Worker lanes start fresh Lua states with the artifact's immutable provider index.
They load and cache their own module instances. Provider objects and closures do
not cross lane boundaries; each consumer chooses during its own initialization.

## Validation

Run behavioral conformance tests on each supported host. Exercise signed bit
operations, JSON markers, buffer ownership, storage interoperability, and
resource lifecycles. Type-check package provider exports against the interfaces
they implement, and test each implementation directly as well as through its
consumer.
