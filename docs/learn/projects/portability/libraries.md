# Portable Lua libraries

Nupp libraries are ordinary Nupp modules. What varies by host is chosen at
require time through SPI providers rather than by building a library twice.

## LuaJIT library modules

The VM provides `bit`, `require("string.buffer")`, and `table.new` and
`table.clear` on the `table` library. The checker also declares `ffi` and the
`jit.*` modules, which are LuaJIT facilities the VM does not have: requiring one
fails at run time.

```nupp
const bit = require("bit")

print(bit.tohex(bit.bswap(0x11223344))) -- 44332211
```

## Require-time selection

SPI covers operations whose implementation varies. Fixed hashing, scalar SIMD,
layout arithmetic, and other ordinary helpers are normal modules.

Implementation interfaces live beside their consuming library in `.spi` modules.
Importing a declaration loads no implementation. Packages advertise their modules
in `nupp/spi.json`; `nupp.spi.load(Interface)` lazily iterates them in dependency
order. The consumer decides what wins.

Standard-library facades choose with `nupp.spi.select`: the unique highest
`priority`, with an omitted priority counting as zero. A highest-priority tie
fails initialization. Empty
discovery uses the facade's explicit target-dependent fallback. Each facade binds
its actual operations during module initialization, so calls perform no SPI lookup.

## Runtime interfaces

[SPI](../spi.md#standard-library-providers) lists each interface and its owning
module. Shared storage, struct, memory-host, and integer declarations remain in
`nupp.mem.representation.spi`; storage and its integer operations must agree.

`nupp.text` owns the portable buffer surface and one shared `Buffer` type.
Its native adapter uses `string.buffer`. Explicitly native pointer and
serialization facilities remain on the native `string.buffer` surface.

GPU providers use the shared interfaces in `nupp.gpu.spi`. Each context retains its
device methods. CPU workgroups and tensor layout operations are ordinary code.
HTTP clients are created with `nupp.io.http.newClient(options)` and retain their
response and body cleanup responsibilities.

Host code pumps network events with `nupp.io.net.pump(milliseconds)`. Process
providers construct exit values with `nupp.io.process.types.exited`.

## Dependency providers

A runtime dependency lists qualified interface names and implementation modules
in `nupp/spi.json`. The build checks ordinary assignment compatibility, including
generic signatures, ownership, and suspension. Lua implementations need a matching
`.d.nupp` declaration or typed adapter. Discovery never executes provider code.

Only target runtime dependencies contribute implementations. See [SPI](../spi.md)
for metadata and examples.

## Workers

Worker lanes each run their own VM with the artifact's immutable provider index.
They load and cache their own module instances. Provider objects and closures do
not cross lane boundaries; each consumer chooses during its own initialization.

## Validation

Type-check provider exports and run behavioral conformance tests on each supported
host. Exercise signed bit operations, JSON markers, buffer ownership, storage
interoperability, and resource lifecycles. Tests using different selections should
initialize separate states. Instrument resolution during module loading and verify
that repeated exported operations leave that count unchanged.
