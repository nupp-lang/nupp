# Calling C safely

Nupp turns C declarations into checked LuaJIT FFI calls. Start by importing a
header, then add ownership and borrowing contracts where the C signature alone
cannot describe lifetime behavior.

There are three ways in, and they suit different sizes of problem:

```
 Route                    Use it when
 ───────────────────────  ─────────────────────────────────────────────
 cdef declarations        The API is small, or you want exact control
 cheader("mini.h")        You want the header typed with no generated file
 nupp import-c mini.h     You want a committed module you can edit
```

## Import a header

Given `native/mini.h`, generate a committed Nupp module:

```bash
nupp import-c native/mini.h --lib mini -o src/native/mini.nupp
```

Write it to a `.nupp` file rather than a `.d.nupp` one. A declaration file is
excluded from runtime module resolution, so the `cdef` statements would never
execute and no binding would exist. Without `-o`, the output is the header's
basename with a `.nupp` extension, in the current directory.

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
The `from` clause loads the named native library through LuaJIT FFI; omit it to
use the default namespace. Both emit an `ffi.cdef` and a namespace lookup:

```lua
pcall(ffi.cdef, "struct nativePoint { double x; double y; };")
local nativePoint = ffi.typeof("struct nativePoint")
pcall(ffi.cdef, "double point_length(struct nativePoint *);")
local point_length = ffi.load("mini").point_length
```

`cdef` bindings are always file-local. Export them by returning them in the
module table, which is what `import-c` generates.

### The type mapping

```
 Nupp                C
 ──────────────────  ────────────────────────
 number              double
 float               float
 boolean             bool
 integer             int32_t
 int8 … int64        int8_t … int64_t
 uint8 … uint64      uint8_t … uint64_t
 cstring             const char *
 voidptr             void *
 T (a cdef struct)   struct T
 T*                  <C spelling> *
 function(A): R      R (*)(A)
```

`cstring` and `voidptr` are allowed in a `cdef struct` but rejected in a plain
Nupp `struct`, because a GC-managed struct gives them no anchor.

Coming the other way, every pointer that `import-c` produces is nullable
(`T*?`), since a C header does not say which pointers may be NULL. Widths come
from the building machine, so `long` and `size_t` are correct per platform.

`import-c` handles scalars, named structs by value and by pointer, function
pointers in parameter position, C varargs, and object-like macros. It leaves an
`-- import-c: skipped` comment for what it will not translate: anonymous
structs, unions, arrays, widths other than 8/16/32/64, function pointers in
return or field position, function-like macros, and names that collide with Lua
keywords.

## Type the header in place

`cheader` reads a header at compile time and gives you its exports, with no
generated file to keep in step:

```nupp
local mini = cheader("native/mini.h", "mini")

print(mini.mini_add(20, 22))
```

The path must be a literal. It is searched relative to the file, then as
written, then against the project roots. The second argument names a library to
load; without it the default namespace is used.

This suits a header that changes often, or one you would rather not vendor a
translation of. `import-c` suits a header you want to prune and annotate, since
its output is yours to edit.

## Typed FFI operations

The six FFI operations take a type argument, which is what makes them checked:

```nupp
local p = ffi.new<nativePoint>()
local q = ffi.cast<nativePoint*>(address)
local t = ffi.typeof<nativePoint>()
local ok = ffi.istype<nativePoint>(value)
local size = ffi.sizeof<nativePoint>()
local align = ffi.alignof<nativePoint>()
```

`ffi.new<T>` and `ffi.cast<T>` return `T`, `ffi.typeof<T>` returns `ctype<T>`,
`ffi.istype<T>` returns `boolean`, and the last two return `integer`. Without a
type argument the checker still reads a constant string spec through LuaJIT's
own parser, so `ffi.new("struct Point")` types too; a spec built at run time
yields `cdata`.

`carray` allocates a zero-based C array:

```nupp
local points = carray(nativePoint, 16)
points[0].x = 1.0
```

That is `carray<T>`, distinct from the one-based Lua array `{T}`.

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
`exclusive` when the call needs sole access for its duration. Use `retains` and
`releases` for pointers C stores beyond a call. Do not use `unsafe` merely to
silence a contract error; use it only where the program must state a fact the
checker cannot prove.

## Build native dependencies reproducibly

For C code that ships with the project, declare a `kind = "c"` dependency in
`nupp.lua` and pin remote sources to an exact revision. Let the build target
depend on it so headers, generated bindings, native libraries, and Nupp
modules share one cache key and one build graph.

See the [build system reference](tooling/build.md) for C and Cargo provider
configuration, [ownership](start/ownership.md) for the resource workflow, and
the [ownership reference](ownership.md) for output parameters, callbacks,
pinning, and raw-pointer escape hatches.

