# Calling C safely

Nupp turns C declarations into checked LuaJIT FFI calls. Start by importing a
header, then add ownership and borrowing contracts where the C signature alone
cannot describe lifetime behavior.

There are three ways in, and they suit different sizes of problem:

| Route | Use it when |
| --- | --- |
| cdef declarations | The API is small, or you want exact control |
| `cheader("mini.h")` | You want the header typed with no generated file |
| nupp import-c mini.h | You want a committed module you can edit |

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

Only the header you name is imported. Whatever arrives through its `#include`s
belongs to those files and is left in them, so the module stays about the API
you asked for rather than the closure behind it. Their typedefs are still read,
because the header is written in them, but their declarations and their macros
are not yours.

That is worth knowing before you point this at a system header, because a
system header is usually a facade: macOS declares `strlen` in `_string.h` and
`EPERM` in `sys/errno.h`, so importing `string.h` or `errno.h` there is correct
and almost empty. Import the file that holds the declarations, or write the few
you need by hand.

Use the generated module like any other:

```nupp:static
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

cdef function point_length(borrows point: nativePoint*): number from"mini"
```

Use Nupp's C-compatible types and preserve the library's exact function name.
The `from` clause loads the named native library through LuaJIT FFI; omit it to
use the default namespace. Both emit an `ffi.cdef` and a namespace lookup:

```lua
pcall(ffi.cdef, "struct nativePoint { double x; double y; };")
const nativePoint = ffi.typeof("struct nativePoint")
pcall(ffi.cdef, "double point_length(struct nativePoint *);")
const point_length = ffi.load("mini").point_length
```

`cdef` bindings are always file-local. Export them by returning them in the
module table, which is what `import-c` generates.

### Type mapping

| Nupp | C |
| --- | --- |
| `number` | double |
| `float` | float |
| `boolean` | bool |
| `integer` | int32_t |
| int8 … int64 | int8_t … int64_t |
| uint8 … uint64 | uint8_t … uint64_t |
| `cstring` | const char * |
| `voidptr` | void * |
| T (a cdef struct) | struct T |
| T* | <C spelling> * |
| function(A): R | R (*)(A) |

`cstring` and `voidptr` are allowed in a `cdef struct` but rejected in a plain
Nupp `struct`, because a GC-managed struct gives them no anchor.

Coming the other way, every pointer that `import-c` produces is nullable
(`T*?`), since a C header does not say which pointers may be NULL. Widths come
from the building machine, so `long` and `size_t` are correct per platform.

`import-c` handles scalars, named structs by value and by pointer, function
pointers in parameter position, C varargs, object-like macros, and enum
members. It leaves an `-- import-c: skipped` comment for what it will not
translate: anonymous structs, unions, arrays, widths other than 8/16/32/64,
function pointers in return or field position, function-like macros, and names
that collide with Lua keywords.

A declaration LuaJIT itself will not parse gets the same comment and does not
take the header with it. That is commonly a struct laid out from a type whose
definition belongs to a header this import left alone. Those are counted on
stderr as `N of M declarations skipped`, and the count is the part to read: one
of thirty is a corner in the header, and most of thirty means the vocabulary
broke upstream and the module is not worth keeping.

An enum's members come across as named `int32` constants:

```nupp
local STATUS_OK: int32 = 0
local STATUS_BUSY: int32 = 1
```

They arrive whether or not the enum itself is named, since `typedef enum { ... }
Mode;` names the type and the members are the point either way. The type is an
integer wherever it appears, which is all a C enum ever is, and C checks nothing
about which integer, so a member passes to the function it belongs to without a
cast, and any other integer passes too. A name declared twice keeps its first
meaning.

## Type the header in place

`cheader` reads a header at compile time and gives you its exports, with no
generated file to keep in step:

```nupp:static
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

```nupp:static
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

```nupp:static
local points = carray(nativePoint, 16)
points[0].x = 1.0
```

That is `carray<T>`, distinct from the one-based Lua array `{T}`.

For larger or explicitly native-owned arrays, use the malloc-backed standard
library allocation and immediately give it bounds:

```nupp
local heap = require("nupp.heap")

local values = heap.allocate(ffi.typeof<int32>(), 1000000)
local writable = values:write()
writable:set(1, 42 as int32)
writable:commit()
```

## C unions and bitfields

`cdef union` shares the same typed field surface as `cdef struct` while emitting
the correct C tag and ABI layout. A second colon gives an integer field its C
bit width:

```nupp
cdef union Value
    integer_value: int32
    number_value: number
end

cdef struct Flags
    ready: uint32 : 1
    mode: uint32 : 3
end
```

`cheader` and `import-c` preserve both forms from C headers.

## JIT-sensitive C boundaries

C-derived callback positions are tracked semantically through declarations and
aliases. Passing a Lua function into one reports `jit-callback` (`NUPP2502`),
and a variadic C call reports `jit-boundary` (`NUPP2514`). Disable the callback
or containing cold function with `jit.off` when the boundary is intentional.
Annotating a function with `@jit` turns either hazard into the non-suppressible
`NUPP2707` contract error.

## Read a struct's layout

`layoutof(T)` answers how a reified `struct` sits in memory:

```nupp
local struct Vertex
    x: float
    y: float
    z: float
end

const layout = layoutof(Vertex)
print(layout.size) -- 12
print(layout.fingerprint) -- x:float,y:float,z:float|12
for _, f in ipairs(layout.fields) do
    print(f.name, f.ctype, f.offset, f.size, f.padding)
end
```

Reifying puts a value where anything that walks a table cannot reach it:
`string.buffer.encode` refuses cdata outright, `pairs` needs a `__pairs`, and
`type` answers `"cdata"`. This is what makes it reachable again without the
language choosing a serialization format. A codec, a snapshot writer, or a GPU
vertex-attribute descriptor is written against the layout, and the format stays
yours.

`size` is a field's own; `padding` is the alignment gap that follows it. They
are separate because they answer different questions. An `int8` before a
`number` has size 1 and padding 7, and a writer walking bytes needs both.

Every number is this platform's, asked of the FFI when the layout is first
built and cached per ctype afterwards. The `fingerprint` therefore describes one
platform's layout, which is what makes it usable for noticing that saved data no
longer matches what is reading it; deciding what to do about a mismatch is the
application's.

A fixed C array is a field like any other, laid out inline:

```nupp
local struct Vertex
    pos: float[3]
    uv: float[2]
    id: int32
end
```

`layoutof` reports `pos` as `float[3]`, twelve bytes wide at offset zero. That
is a vertex attribute descriptor, and is what makes one derivable rather than
hand-maintained. `T[?]` is not a field: a struct whose size depends on a count
nobody wrote has no size, so it stays **NUPP2201**.

Only a `struct` has a layout. A `record` is a table, so `layoutof` on one is
**NUPP2402**. Nothing is emitted for a struct nothing asks about: the lowering
happens at the call site, so a program that never calls `layoutof` carries none
of this.

## Describe lifetime behavior

C types do not reveal who frees a returned pointer. Add that fact explicitly:

```nupp
cdef struct nativeBuffer
    size: uint64
end

cdef function buffer_free(takes buffer: nativeBuffer*) from"mini"

@owned(buffer_free)
cdef function buffer_create(size: uint64): nativeBuffer* from"mini"

do
    local buffer = buffer_create(4096)
    print(buffer.size)
end
```

`@owned(buffer_free)` says the caller receives one cleanup obligation.
`takes` says `buffer_free` consumes it. The lexical owner guarantees cleanup
across fallthrough, errors, and structured control flow.

Use `borrows` when C only observes a resource for the duration of a call, and
`exclusive` when the call needs sole access for its duration. Use `retains` and
`releases` for pointers C stores beyond a call. Do not use `unsafe` merely to
silence a contract error; use it only where the program must state a fact the
checker cannot prove.

## Counted pointer adapters

`countedBy(count)` relates a call-duration borrowed C pointer to its physical
element count. The qualifier does not change the C ABI given to LuaJIT FFI,
while checked callers see spans:

```nupp
cdef function transform(
    borrows output: Item* countedBy(count),
    borrows input: const Item* countedBy(count),
    count: uint64
)
```

The logical parameters are `exclusive output: span.WriteSpan<Item>` and
`borrows input: span.Span<Item>`; `count` is supplied from the spans. Pointers
sharing a count must have equal logical lengths. The wrapper checks equality
before projecting either pointer and calls C exactly once, including at count
zero. The foreign implementation must not dereference a mapped pointer when
its count is zero.

Const pointers become shared spans and mutable pointers become writable spans.
Counted pointers must use `borrows`, and counts currently use plain `uint64`.
Strides, byte counts, capacities, prefixes, sentinel termination, output
pointers, and retained pointers require handwritten `ref()` wrappers.

## Build native dependencies reproducibly

For C code that ships with the project, declare a `kind = "c"` dependency in
`nupp.lua` and pin remote sources to an exact revision. Let the build target
depend on it so headers, generated bindings, native libraries, and Nupp
modules share one cache key and one build graph.

See the [build system reference](tooling/build.md) for C and Cargo provider
configuration, [ownership](start/ownership.md) for the resource workflow, and
the [ownership reference](ownership.md) for output parameters, callbacks,
pinning, and raw-pointer escape hatches.

## Diagnostics

- **NUPP2201**: a struct field is not reifiable, which a `T[?]` field reports
  because a struct whose size depends on a runtime count has none.
- **NUPP2402**: `layoutof` was asked about something with no layout, such as a
  `record`, which is a table rather than C memory.

## Next

- [ownership.md](ownership.md): the contracts a C pointer crosses the boundary with.
- [records.md](type-system/records.md): the struct declarations a header imports as.
