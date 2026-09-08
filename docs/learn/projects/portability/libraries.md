# Portable Lua libraries

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
native target; registering a provider cannot change that requirement.

## Require-time selection

SPI covers operations whose implementation varies. Fixed hashing, scalar SIMD,
layout arithmetic, and other ordinary helpers are normal modules.

Canonical interfaces and handles live under `nupp.runtime.services`. Importing a
contract defines its handle without loading its implementations. A setup entry
can select a named provider before requiring application modules:

```nupp
module setup
local contracts = require("nupp.runtime.services.contracts")
contracts.bitops:select("nupp.scalar")
return require("application")
```

Use `setup` as the target entry. A consuming facade resolves its provider during
`require`, retains the resulting table, and exports its actual operations. Lua's
module cache retains that assembled module. Calls perform no SPI lookup.

An explicit selection wins. Without one, a facade chooses its documented built-in
default with ordinary conditions. Discovering a third-party provider never makes
it the default. Once the facade resolves, its default selection is frozen;
reselection fails. A failed loader, invalid implementation, missing required
provider, or dependency cycle fails the require with service context.

## Runtime contracts

| Handle | Interface and consumer |
| --- | --- |
| `contracts.bitops` | Signed, variadic word operations; `nupp.runtime.bitops` |
| `contracts.buffer` | Portable buffers; `nupp.text.buffer` |
| `contracts.json` | JSON values and markers; `nupp.codec.json` |
| `contracts.cstorage` | Target storage and its representation operations |
| `contracts.path`, `contracts.uri` | Path and URI operations |
| `contracts.time` | Clock and timer operations; `nupp.time` |
| `contracts.uuid`, `contracts.crypto`, `contracts.storage` | UUIDs, host cryptography, and persistent storage |
| `services.suspension.service` | Suspension and cancellation |
| `services.workers.service` | Isolated worker execution |
| `services.http.service` | HTTP clients and responses |
| `services.gpu.service` | GPU devices sharing canonical buffer and context types |
| `services.net.service`, `services.process.service`, `services.tls.service` | Network, process, and TLS transports |

Here `contracts` names `nupp.runtime.services.contracts`, and `services.*` names
the corresponding module under `nupp.runtime.services`.

`nupp.text.buffer` owns the portable buffer surface and one shared `Buffer` type.
Its native adapter uses LuaJIT's `string.buffer`. Explicitly native pointer and
serialization facilities remain on the native `string.buffer` surface.

GPU providers use the shared interfaces in `nupp.runtime.services.gpu`. Each context retains its
device methods. CPU workgroups and tensor layout operations are ordinary code.
HTTP clients are created with `nupp.io.http.client(options)` and retain their
response and body cleanup responsibilities.

Host code pumps network events with `nupp.io.net.pump(milliseconds)`. Process
providers construct exit values with `nupp.io.process.types.exited`.

## Dependency providers

A runtime dependency advertises a canonical contract module, handle export, API
version, provider name, and implementation export in its static descriptor. The
build checks that export against the contract, including generic signatures,
ownership, and suspension guarantees. Additional members are allowed. Lua
implementations need a matching `.d.nupp` declaration or a typed adapter.

The artifact catalog contains target-compatible implementations from the runtime
dependency graph. Discovery and checking never execute provider code. Native
adapters remain separately loadable and are excluded from portable payloads.
Only target dependencies contribute runtime providers.

See [Service Providers](../service-providers.md) for descriptors and the typed API.

## Workers

Worker lanes start fresh Lua states. Before loading consumers, child initialization
loads explicit setup modules and replays catalog-backed named selections. Provider
instances and loader closures do not cross the lane boundary.

Register a setup module with `nupp.services.setupWorkers("workersetup")` before
requiring consumers, and include that module in the artifact's entry modules.
Runtime-only registrations need explicit setup in the destination lane. Each lane
loads and caches its own provider instances.

## Validation

Type-check provider exports and run behavioral conformance tests on each supported
host. Exercise signed bit operations, JSON markers, buffer ownership, storage
interoperability, and resource lifecycles. Tests using different selections should
initialize separate states. Instrument resolution during module loading and verify
that repeated exported operations leave that count unchanged.
