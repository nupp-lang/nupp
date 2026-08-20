# Calling C safely

Nupp turns C declarations into checked LuaJIT FFI calls. Start by importing a
header, then add ownership and borrowing contracts where the C signature alone
cannot describe lifetime behavior.

There are four ways to bring C declarations in, and one canonical way to
publish ordinary Nupp structs to C:

| Route | Use it when |
| --- | --- |
| cdef declarations | The API is small, or you want exact control |
| `cheader("mini.h")` | You want the header typed with no generated file |
| nupp import-c mini.h | You want a committed module you can edit |
| `bindings.bridge` in `nupp.lua` | The header contains `static inline` functions or typed function-like macros |
| nupp export-c -o mini.h ... | C needs to consume Nupp struct layouts |

The smallest of them is one declaration:

```nupp
cdef function abs(value: int32): int32

const magnitude = abs(-3)
```

::: rationale
A declaration is direct, bridged, or skipped for one reported reason — never
substituted with a generic pointer or a guessed ABI, which would produce a
declaration that checks, links, and is wrong at run time. The header supplies
physical facts only: what a call borrows, takes, retains, or releases is not in
the header, so deriving it would be invention at exactly the boundary where
invention is most expensive.

[NEP 9](../neps/0009-c-interop-and-embedding.md) has the full record.
:::

## Export ordinary structs to C

Define an ordinary reified struct once in Nupp, then select it and any typed C
entry points that use it:

```bash
nupp export-c -o game.h src/game.nupp game.Position game.integrate
```

The command emits a deterministic, include-guarded C header. Each ordinary
struct receives a collision-safe module-qualified typedef, a semantic and
target-layout fingerprint, and static assertions for its size, alignment, and
every field offset. Embedded structs are ordered by value; pointer-recursive
types use forward declarations. The configured target's `layoutTarget` is the
authority, so generation never guesses from the build host and never invokes a
C compiler.

An ordinary struct may appear behind a pointer or array in a `cdef function`:

```nupp
module game

export struct Position
    x: float
    y: float
end

cdef function integrate(exclusive position: Position*, dt: float)
```

The emitted prototype stays typed. Internally LuaJIT receives a compiler-owned
`void *` physical slot because Nupp's sole runtime representation remains the
existing anonymous ctype; source checking, ownership, constness, counted
relationships, and the external C definition all retain the ordinary struct
type. Ordinary structs do not cross this boundary by value. `export-c` is the
only publisher: there is no annotation, user-selected C tag, or parallel header
generator.

## Import a header

Given `native/mini.h`, generate a committed Nupp module:

```bash
nupp import-c native/mini.h --lib mini -o src/native/mini.nupp
```

Write it to a `.nupp` file rather than a `.d.nupp` one. A declaration file is
excluded from runtime module resolution, so the `cdef` statements would never
execute and no binding would exist. Without `-o`, the output is the header's
basename with a `.nupp` extension, in the current directory.

The generated file declares the canonical module derived from its output path,
contains `cdef struct` and `cdef function` declarations, and exports the
resulting binding table with `export =`. It is deliberately hand-editable.
Review it, remove declarations your program does not use, and add contracts the
header cannot express.

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

```nupp:playground
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

`cdef` bindings are always file-local. Export them through a declared module;
`import-c` collects them into its final `export =` migration boundary.

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
pointers in parameters, results, aggregate fields and nested declarators, fixed
arrays, typedef-named anonymous structs and unions, C varargs, object-like
macros, and enum members. Fixed arrays retain every bound (`T[N]`), including
arrays nested in fields or behind pointers. It leaves an `-- import-c: skipped`
comment for flexible arrays, anonymous-member promotion, unsupported scalar
widths or calling conventions, and names that collide with Lua keywords.

For example, this header exercises the declarators which are easiest to lose in
a source generator:

```c
#include <stdint.h>

typedef void (*visit_fn)(int32_t value);

typedef struct {
    float matrix[2][3];
    visit_fn callback;
} context;

void use_context(context *value);
visit_fn get_callback(void);
void set_callbacks(visit_fn callbacks[4]);
int32_t (*get_row(void))[4];
```

`nupp import-c complete.h -o complete.nupp` preserves every nested part:

```nupp
cdef struct context
   matrix: float[3][2]
   callback: function(int32)?
end

cdef function use_context(value: context*?)
cdef function get_callback(): function(int32)?
cdef function set_callbacks(callbacks: function(int32)?*?)
cdef function get_row(): int32[4]*?
```

Nupp writes nested C array declarators from the element outward, so C
`float[2][3]` is `float[3][2]`: three floats make an inner row and two rows make
the field. A C array parameter is adjusted to a pointer by C itself, which is
why `callbacks[4]` becomes a pointer while the pointer-to-array result retains
its `[4]` bound. Function pointers and ordinary pointers are nullable: the
current importer does not infer a nonnull contract from a header. A
`const char *` is the nullable string-taking form `cstring?`.

The anonymous struct is public as `context`, its typedef identity. The same
rule applies to typedef-named anonymous unions. Anonymous members which promote
their fields into an enclosing aggregate are deliberately skipped because Nupp
does not yet have the corresponding member-access semantics.

A declaration LuaJIT itself will not parse gets the same comment and does not
take the header with it. That is commonly a struct laid out from a type whose
definition belongs to a header this import left alone. Those are counted on
stderr as `N of M declarations skipped`, and the count is the part to read: one
of thirty is a corner in the header, and most of thirty means the vocabulary
broke upstream and the module is not worth keeping.

### Header-only functions

A `static inline` function has a callable C type but no exported symbol for
LuaJIT to load. A function-like macro has neither a symbol nor a C type. A
bridge turns either one into an ordinary exported function in the native
dependency while leaving its logical Nupp name unchanged.

The bridge is opt-in. A direct import of this header reports both inline
functions as skipped rather than generating a library behind your back:

```c [native/image.h]
#ifndef IMAGE_H
#define IMAGE_H

#include <stdint.h>

static inline int32_t image_triple(int32_t value)
{
    return value * 3;
}

static inline void image_store(int32_t *slot, int32_t value)
{
    *slot = value;
}

#define IMAGE_CLAMP(value, low, high) \
    ((value) < (low) ? (low) : ((value) > (high) ? (high) : (value)))
#define IMAGE_IGNORE(value) ((void)(value))

#endif
```

#### Build the bridge with the project

The preferred route is a C dependency because the build then owns the compiler
flags, shared library, binding module, cache key, and packaging together. A
header-only dependency needs no dummy `.c` file:

```lua [nupp.lua]
return {
   include = { "src" },

   dependencies = {
      image = {
         kind = "c",
         includeDirs = { "native" },
         headers = { "native/**/*.h" },
         bindings = {
            header = "native/image.h",
            bridge = true,
            macros = {
               IMAGE_CLAMP = {
                  parameters = { "int32", "int32", "int32" },
                  result = "int32",
               },
               IMAGE_IGNORE = {
                  parameters = { "int32" },
               },
            },
         },
      },
   },

   build = {
      outDir = "build",
      entries = { "main" },
      dependencies = { "image" },
   },
}
```

`bridge = true` selects eligible `static inline` definitions in the named
header. Each entry in `macros` independently requests one function-like macro
and supplies the type C itself does not provide. Omitting `result` means the
wrapper returns `void`, as `IMAGE_IGNORE` does above. The admitted recipe types
are:

| Recipe spelling | Wrapper C type |
| --- | --- |
| `boolean` | `_Bool` |
| `float` | `float` |
| `number` | `double` |
| `integer` | `int32_t` |
| `int8`, `int16`, `int32`, `int64` | matching signed fixed-width integer |
| `uint8`, `uint16`, `uint32`, `uint64` | matching unsigned fixed-width integer |

Recipes are positional and fixed-arity. The build rejects a missing macro, a
variadic macro, an arity mismatch, or any other type spelling before installing
a partial binding. Pointer recipes are intentionally rejected: the recipe
would otherwise conceal whether the macro borrows, retains, releases, or writes
through the pointer. Use a handwritten C wrapper and an ownership-refined
`cdef` for that boundary.

After `nupp build`, the generated module has the dependency's name:

```nupp [src/main.nupp]
local image = require("image")

print(image.image_triple(14))       -- 42
print(image.IMAGE_CLAMP(20, 2, 8)) -- 8
image.IMAGE_IGNORE(42)
```

The build writes three artifacts on macOS, using the corresponding platform
library suffix elsewhere:

```text
build/generated/image.nupp
build/generated/image_bridge.c
build/lib/libimage.dylib
```

The Nupp module binds deterministic private symbols such as
`__nupp_bridge_<fingerprint>`, then aliases them back to `image_triple` and
`IMAGE_CLAMP`. Application code uses only those logical names. The generated C
includes `native/image.h`; it does not copy or translate the inline body or
macro expansion. The selected C compiler remains the
authority, and changing the header, macro recipes, flags, compiler identity, or
bridge source invalidates the dependency build.

The generated binding has this shape; the real suffix is a 24-character
hexadecimal digest:

```nupp
cdef function __nupp_bridge_fingerprint(value: int32): int32 from "@lib/libimage.so"
local image_triple = __nupp_bridge_fingerprint

return { image_triple = image_triple }
```

The leading `@` names the library relative to the module that loads it rather
than to the platform loader or to where the build ran, which is what makes the
output tree relocatable: copy or move it and the binding still finds its
library. A `bindings.library` override, a `load` naming a library already on the
system, and a `pkgConfig` package are left exactly as written, since none of
them travel with the build.

Every Nupp argument is evaluated before the FFI call. A macro may mention its C
parameter more than once, but it cannot re-evaluate the Nupp expression which
produced the wrapper argument.

#### Emit a standalone bridge

`import-c` can emit the same inline wrappers without compiling them. This is
useful when an external build system owns the native library:

```bash
mkdir -p build/generated build/lib src/native

nupp import-c native/image.h \
  --lib build/lib/libimage.so \
  --bridge-out build/generated/image_bridge.c \
  -o src/native/image.nupp

cc -shared -fPIC -I. \
  -o build/lib/libimage.so build/generated/image_bridge.c
```

That compiler command is the Linux form. On macOS use `-dynamiclib` and a
`.dylib` output. In a real build, pass the same include directories,
preprocessor definitions, language standard, target, and required warning
flags as the header's native library. `--bridge-out` handles eligible inline
functions only; standalone macro signatures belong in the checked manifest, so
macros need either a project dependency or a handwritten wrapper.

The emitted C is deliberately small:

```c
#include <stdint.h>
#if defined(_WIN32)
#define NUPP_BRIDGE_EXPORT __declspec(dllexport)
#else
#define NUPP_BRIDGE_EXPORT __attribute__((visibility("default")))
#endif
#include "native/image.h"

NUPP_BRIDGE_EXPORT int32_t __nupp_bridge_fingerprint(int32_t value) {
    return image_triple(value);
}
```

`--lib` must name the artifact which actually contains the wrappers. The
command only writes the requested Nupp and C files; it does not invent a
compiler invocation, create a library, or arrange a runtime search path.

#### Inspect coverage before generating files

Inspection performs preprocessing and declaration analysis but writes no
module, bridge, or native library:

```bash
nupp import-c native/image.h --inspect
# direct 0, bridged 0, skipped 2

nupp import-c native/image.h --inspect --json
```

The JSON result contains totals, warnings, and dispositions for each considered
aggregate or callable:

```json
{
  "ok": true,
  "direct": 0,
  "bridged": 0,
  "skipped": 2,
  "warnings": [
    "static inline image_triple needs a configured C bridge",
    "static inline image_store needs a configured C bridge"
  ],
  "dispositions": [
    {"name": "image_triple", "kind": "skipped", "reason": "bridge-required"},
    {"name": "image_store", "kind": "skipped", "reason": "bridge-required"}
  ]
}
```

To preview inline bridge eligibility without writing the named bridge, combine
`--bridge-out` with `--inspect`. Inspection still wins over output, while the
flag makes eligible entries report `bridge-inline` and include their private
`symbol`:

```bash
nupp import-c native/image.h \
  --bridge-out ignored.c --inspect --json
```

Disposition kinds are stable integration data:

| Kind | Meaning |
| --- | --- |
| `direct` | An externally addressable C function is bound directly |
| `type-only` | An aggregate declaration was imported for use by callables |
| `bridge-inline` | A `static inline` definition received a wrapper |
| `bridge-macro` | An explicitly typed function-like macro received a wrapper |
| `skipped` | No safe lowering exists; `reason` says why |

Common skip reasons include `bridge-required`, `parse-failure`,
`unsupported-c-type`, `unsupported-field-type`,
`unsupported-bridge-type`, and `invalid-macro-signature`. The generated module
also retains readable `-- import-c: skipped` comments, so a non-JSON workflow
does not hide incomplete coverage.

#### Refine the generated ownership contract

A header supplies physical types, not lifetimes or effects. Bridge generation
does not infer that a pointer is borrowed, retained, released, counted, or
initialized on success. The generated module is intentionally editable, so
refine the declaration after reviewing the API contract:

```nupp
-- Generated physical type:
cdef function use_context(value: context*?)

-- Reviewed contract: the callee only reads it during this call.
cdef function use_context(borrows value: context*?)
```

For a bridged callable, add the mode to its private generated `cdef function`;
the logical local alias receives that checked function type. Keep an owned
callback pinned for as long as C may call it. The ordinary callback/JIT warning
also applies through nullable callback fields, parameters, results, arrays, and
pointer nesting.

#### Current boundary

The direct importer and bridge deliberately refuse shapes for which they do
not have one proven physical meaning:

- C++ declarations, compiler vector extensions, `long double`, `_Complex`,
  inline assembly, and unmodelled calling conventions;
- flexible and variable-length arrays, incomplete by-value aggregates, and
  anonymous-member promotion;
- arbitrary preprocessor programs, variadic macros, pointer-bearing macro
  recipes, and expansions which are not valid in the generated return
  expression or void statement;
- an inline definition whose signature LuaJIT cannot represent, or which is
  not an eligible named `static inline` definition in the selected header.

Included headers provide typedef vocabulary but their declarations and macros
are not swept into the requested module. Direct layout and calling facts are
currently host LuaJIT facts; rich Clang extraction, ABI witnesses, and complete
cross-target bridge emission remain future work. An unsupported declaration is
skipped with a reason rather than widened to `any` or a plausible-looking
`voidptr`.

An enum's members come across as named `int32` constants:

```nupp
local STATUS_OK: int32 = 0
local STATUS_BUSY: int32 = 1
```

They arrive whether or not the enum itself is named, since
`typedef enum { ... } Mode;` names the type and the members are the point either
way. The type is an integer wherever it appears, which is all a C enum ever is,
and C checks nothing about which integer, so a member passes to the function it
belongs to without a cast, and any other integer passes too. A name declared
twice keeps its first meaning.

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
its output is yours to edit. `cheader` uses the same direct declaration model
for fixed arrays, typedef-named anonymous aggregates, exact pointer nesting,
and callback fields, parameters and results. It never compiles a bridge:
header-only callables still require the manifest dependency or standalone
`--bridge-out` workflow above.

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

For larger or explicitly native-owned arrays, use the malloc-backed standard
library allocation and immediately give it bounds:

```nupp
local heap = require("nupp.mem.heap")

local values = heap.allocate(ffi.typeof<int32>(), 1000000)
local writable = values:write()
writable[1] = 42 as int32
drop writable
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

A third hazard is not about C at all: LuaJIT cannot record the bytecode that
builds a function, so a loop containing one never compiles. `@jit` reports that
as the same contract error, and `jit.off` on the enclosing function silences it
the same way. Outside `@jit` it is `jit-loop-closure` (`NUPP2515`), off until a
project asks for it; see [lints](../reference/lints.md).

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

C types do not reveal who frees a returned pointer. Say it in the result type:

```nupp
cdef struct nativeBuffer
    size: uint64
end

cdef function buffer_free(takes buffer: nativeBuffer*) from"mini"

cdef function buffer_create(size: uint64): affine(nativeBuffer*, buffer_free) from"mini"

do
    local buffer = buffer_create(4096)
    print(buffer.size)
end
```

`affine(nativeBuffer*, buffer_free)` says the caller receives one cleanup
obligation and names what discharges it. `takes` says `buffer_free` consumes
it. The lexical owner guarantees cleanup across fallthrough, errors, and
structured control flow.

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

See [checked spans](../modules/nupp/mem/span.md) for construction, slicing,
partitioning, and shared-range validation.

## Build native dependencies reproducibly

For C code that ships with the project, declare a `kind = "c"` dependency in
`nupp.lua` and pin remote sources to an exact revision. Let the build target
depend on it so headers, generated bindings, native libraries, and Nupp
modules share one cache key and one build graph.

See the [build system reference](../guides/build.md) for C and Cargo provider
configuration, [ownership](ownership.md) for the resource workflow, and the
[ownership reference](../type-system/ownership.md) for output parameters,
callbacks, pinning, and raw-pointer escape hatches.

## FAQ

### Does checked C interop replace LuaJIT FFI?

Nupp does not replace LuaJIT FFI or insert a foreign-call runtime. A checked
[`cdef` binding](#hand-write-a-small-binding) lowers to `ffi.cdef`, a namespace
lookup, and the same native call. The [typed FFI
operations](#typed-ffi-operations) likewise retain their LuaJIT representation
while the checker validates their type arguments.

### Does importing a header capture ownership?

A C declaration says that a value is a pointer, but not whether the caller must
free it, whether the callee retains it, or how long a derived pointer remains
valid. Add those facts under [lifetime behavior](#describe-lifetime-behavior)
after importing a header. The [ownership
reference](../type-system/ownership.md#borrowing-and-pinning) defines the
corresponding borrowing, pinning, retention, and cleanup contracts.

### Do ownership contracts change the native ABI?

`affine(T, cleanup)`, `borrows`, `exclusive`, and `countedBy` describe checked
relationships around a call; they do not add fields or change its C signature.
An [affine pointer keeps its ABI
representation](../type-system/ownership.md#c-interop), and a [counted pointer
adapter](#counted-pointer-adapters) projects a checked span onto the pointer and
count the function already accepts.
