# Calling C safely

Nupp turns C declarations into checked LuaJIT FFI calls. Start by importing a
header, then add ownership and borrowing contracts where the C signature alone
cannot describe lifetime behavior.

## Import a header

Given `native/mini.h`, generate a committed Nupp module:

```bash
nupp import-c native/mini.h --lib mini -o src/native/mini.nupp
```

The generated file contains `cdef struct` and `cdef function` declarations
plus a returned module table. It is deliberately hand-editable. Review it,
remove declarations your program does not use, and add contracts the header
cannot express.

Use the generated module like any other:

```nupp
local miniApi = require("native.mini")

local total = miniApi.mini_add(20, 22)
print(total)
```

Nupp-written names use camelCase. Imported declarations such as `mini_add`
keep the C library's spelling because those names identify ABI symbols. A
camelCase local such as `miniApi` makes the boundary clear without disguising
the foreign symbol.

## Hand-write a small binding

For a tiny API, a direct declaration can be clearer than importing a large
header:

```nupp
cdef struct nativePoint
   x: number
   y: number
end

cdef function point_length(borrows point: nativePoint*): number from "mini"
```

Use Nupp's C-compatible types and preserve the library's exact function name.
The `from` clause loads the named native library through LuaJIT FFI.

## Describe lifetime behavior

C types do not reveal who frees a returned pointer. Add that fact explicitly:

```nupp
cdef struct nativeBuffer
   size: uint64
end

cdef function buffer_free(takes buffer: nativeBuffer*) from "mini"

@owned(buffer_free)
cdef function buffer_create(size: uint64): nativeBuffer* from "mini"

with buffer = buffer_create(4096) do
   print(buffer.size)
end
```

`@owned(buffer_free)` says the caller receives one cleanup obligation.
`takes` says `buffer_free` consumes it. `with` guarantees cleanup across
fallthrough, errors, and structured control flow.

Use `borrows` when C only observes a resource for the duration of a call, and
`inout` when the call needs exclusive temporary access. Use `retains` and
`releases` for pointers C stores beyond a call. Do not use `unsafe` merely to
silence a contract error; use it only where the program must state a fact the
checker cannot prove.

## Build native dependencies reproducibly

For C code that ships with the project, declare a `kind = "c"` dependency in
`nupp.lua` and pin remote sources to an exact revision. Let the build target
depend on it so headers, generated bindings, native libraries, and Nupp
modules share one cache key and one build graph.

See the [build system reference](../build/index.html) for C and Cargo provider
configuration. See [managing resources](../managing-resources/index.html) for
the ownership workflow and the [ownership reference](../ownership/index.html)
for output parameters, callbacks, pinning, and raw-pointer escape hatches.

