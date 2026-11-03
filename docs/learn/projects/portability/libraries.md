# Portable Lua libraries

Nupp libraries are ordinary Nupp modules. What varies by host is bound to the
selected target by the build, so a library is written once for every host.

## LuaJIT library modules

The VM provides `bit`, `require("string.buffer")`, and `table.new` and
`table.clear` on the `table` library. The checker also declares `ffi` and the
`jit.*` modules, which are LuaJIT facilities the VM does not have: requiring one
fails at run time.

```nupp
print(bit.tohex(bit.bswap(0x11223344))) -- 44332211
```

## Target implementations

The build binds builtin implementations for the selected native or browser
host. Standard-library calls use those bindings; package descriptors do not
replace them. Fixed hashing, scalar SIMD, and layout arithmetic remain ordinary
modules.

Storage and struct operations use private runtime contracts. Their layouts and
scalar codecs agree with the representation compiled into the program.
`nupp.text` owns the portable buffer surface and one shared `Buffer` type.
Its native adapter uses `string.buffer`. Explicitly native pointer and
serialization facilities remain on the native `string.buffer` surface.

Each GPU context retains its device methods. CPU workgroups and tensor layout
operations are ordinary code. HTTP clients are created with
`io.http.newclient(options)` and retain their response and body cleanup
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

Worker lanes each run their own VM with the artifact's immutable provider index.
They load and cache their own module instances. Provider objects and closures do
not cross lane boundaries; each consumer chooses during its own initialization.

## Validation

Run behavioral conformance tests on each supported host. Exercise signed bit
operations, JSON markers, buffer ownership, storage interoperability, and
resource lifecycles. Type-check package provider exports against the interfaces
they implement, and test each implementation directly as well as through its
consumer.
