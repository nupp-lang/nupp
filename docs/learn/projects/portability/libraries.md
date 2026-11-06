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
host, and standard-library calls use those bindings. Fixed hashing, scalar SIMD,
and layout arithmetic remain ordinary modules.

Storage and struct operations use private runtime contracts. Their layouts and
scalar codecs agree with the representation compiled into the program.
[](string.buffer) owns the canonical FIFO `Buffer` type on native and browser
hosts. Its pointer and serialization operations retain their native
representation and lifetime requirements.

Each GPU context retains its device methods. CPU workgroups and tensor layout
operations are ordinary code. HTTP clients are created with
`io.http.Client.create(options)` and retain their response and body cleanup
responsibilities.

Host code pumps network events with `io.net.pump(milliseconds)`. Processes
return plain `io.Process.Exit` data containing `exitcode`, `killed`, and
`timedout`.

## Workers

Worker lanes each run their own VM over the same immutable artifact. They load
and cache their own module instances. Provider objects and closures do not cross
lane boundaries; each consumer binds its implementation during its own
initialization.

## Validation

Run behavioral conformance tests on each supported host. Exercise signed bit
operations, JSON markers, buffer ownership, storage interoperability, and
resource lifecycles. Type-check package provider exports against the interfaces
they implement, and test each implementation directly as well as through its
consumer.
