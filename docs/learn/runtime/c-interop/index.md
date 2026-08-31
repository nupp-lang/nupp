---
order: 160
---

# C interop

Nupp turns C declarations into checked LuaJIT FFI calls, with no foreign-call
runtime of its own. Reach for it to call a C library, and add ownership
contracts where a C signature cannot describe lifetime behavior.

```nupp:playground
cdef function abs(value: int32): int32

print(abs(-3))
```

Declarations arrive by one of four routes:

- Hand-written `cdef` declarations, when the API is small or exact control
  matters.
- `cheader("mini.h")`, when the header should be typed with no generated file
  to keep in step.
- `nupp import-c mini.h`, when a committed module you can edit is worth having.
- `bindings.bridge` in `nupp.lua`, when the header holds `static inline`
  functions or typed function-like macros.

Going the other way, `nupp export-c` publishes ordinary Nupp struct layouts for
C to consume.

## Hand-write a small binding

For a tiny API, a direct declaration is clearer than importing a large header:

```nupp
cdef struct nativePoint
    x: number
    y: number
end

cdef function point_length(borrows point: nativePoint*): number from"mini"
```

Use Nupp's C-compatible types and preserve the library's exact function name.
The `from` clause loads the named native library through LuaJIT FFI; omit it to
use the default namespace. Both forms lower to an `ffi.cdef` and a namespace
lookup:

```lua [Generated Lua]
pcall(ffi.cdef, "struct nativePoint { double x; double y; };")
const nativePoint = ffi.typeof("struct nativePoint")
pcall(ffi.cdef, "double point_length(struct nativePoint *);")
const point_length = ffi.load("mini").point_length
```

`cdef` bindings are always file-local. Export them through a declared module,
as `import-c` does when it collects its declarations into one `export =`
boundary. See [modules.md](../../language/modules.md) for how that boundary is declared.

### Type mapping

Every `cdef` field and parameter has to render as literal C, which these
types do:

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
| T* | <C type name> * |
| function(A): R | R (*)(A) |

`cstring` and `voidptr` are allowed in a `cdef struct` but rejected in a plain
Nupp `struct`, because a GC-managed struct gives them no anchor.

A type C cannot represent is reported rather than widened. A `cdef`
declaration refuses a pointer to a plain `record`, a typed FFI operation refuses
a record as its type argument, and a reified `struct` refuses a field the
generator cannot render, such as an array of pointers.

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
holds `cdef struct` and `cdef function` declarations, and exports the resulting
binding table with `export =`. It is deliberately hand-editable: review it,
remove declarations your program does not use, and add the contracts the header
cannot express.

Use the generated module like any other:

```nupp
local miniApi = require("native.mini")

local total = miniApi.mini_add(20, 22)
print(total)
```

Nupp-written names use camelCase. An imported declaration such as `mini_add`
keeps the C library's name, because that name identifies an ABI symbol. A
camelCase local such as `miniApi` marks the boundary without disguising the
foreign symbol.

::: deepdive
Each declaration is imported directly, bridged, or skipped for one reported
reason. None is substituted with a generic pointer or a guessed ABI, which
would produce a declaration that checks, links, and is wrong at run time.

The header supplies physical facts only. What a call borrows, takes, retains,
or releases is not written in it, so deriving those facts would be invention at
exactly the boundary where invention is most expensive.

See [NEP 8](../../../neps/0008-c-interop-and-embedding.md) for more information.
:::

### Included headers

Only the header you name is imported. Whatever arrives through its `#include`s
belongs to those files and stays in them, so the module is about the API you
asked for rather than the closure behind it. Their typedefs are still read,
because the header is written in them, but their declarations and their macros
are not yours.

That matters most for a system header, which is usually a facade: macOS
declares `strlen` in `_string.h` and `EPERM` in `sys/errno.h`, so importing
`string.h` or `errno.h` there is correct and almost empty. Import the file that
holds the declarations, or write the few you need by hand.

### Nullable pointers and platform widths

Every pointer `import-c` produces is nullable (`T*?`), since a C header does not
say which pointers may be NULL, and a `const char *` arrives as `cstring?`. The
importer infers no nonnull contract from a header. Widths come from the building
machine, so `long` and `size_t` are correct per platform.

### Declarators that survive an import

`import-c` handles scalars, named structs by value and by pointer, function
pointers in parameters, results, aggregate fields and nested declarators, fixed
arrays, typedef-named anonymous structs and unions, C varargs, object-like
macros, and enum members. A fixed array retains every bound (`T[N]`), including
one nested in a field or behind a pointer.

This header exercises the declarators that are easiest to lose in a source
generator:

```c [complete.h]
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

```nupp [complete.nupp]
cdef struct context
   matrix: float[3][2]
   callback: function(int32)?
end

cdef function use_context(value: context*?)
cdef function get_callback(): function(int32)?
cdef function set_callbacks(callbacks: function(int32)?*?)
cdef function get_row(): int32[4]*?
```

Nupp writes a nested C array declarator from the element outward, so C
`float[2][3]` is `float[3][2]`: three floats make an inner row, and two rows
make the field. A C array parameter is adjusted to a pointer by C itself, which
is why `callbacks[4]` becomes a pointer while the pointer-to-array result keeps
its `[4]` bound.

The anonymous struct is public as `context`, its typedef identity, and the same
rule applies to a typedef-named anonymous union.

### Enum members

An enum's members come across as named `int32` constants:

```nupp
local STATUS_OK: int32 = 0
local STATUS_BUSY: int32 = 1
```

They arrive whether or not the enum itself is named, since
`typedef enum { ... } Mode;` names the type and the members are the point
either way. The type is an integer wherever it appears, which is all a C enum
ever is, and C checks nothing about which integer, so a member passes to the
function it belongs to without a cast, and any other integer passes too. A name
declared twice keeps its first meaning.

### Skipped declarations

An unsupported declaration is skipped with a reason rather than widened to
`any` or a plausible-looking `voidptr`. The generated module keeps an
`-- import-c: skipped` comment for a flexible array, an unsupported scalar
width or calling convention, and a name that collides with a Lua keyword. An
anonymous member whose fields would promote into an enclosing aggregate is
skipped too, because Nupp has no member-access semantics for that promotion
yet.

A declaration LuaJIT itself will not parse gets the same comment and does not
take the header down with it. That is commonly a struct laid out from a type
whose definition belongs to a header this import left alone.

Skips are counted on stderr as `N of M declarations skipped`, and the count is
the part to read: one of thirty is a corner in the header, and most of thirty
means the vocabulary broke upstream and the module is not worth keeping.

## Header-only functions

A `static inline` function has a callable C type but no exported symbol for
LuaJIT to load, and a function-like macro has neither a symbol nor a C type. A
bridge turns either one into an ordinary exported function in the native
dependency, leaving its logical Nupp name unchanged.

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

### Build the bridge with the project

A C dependency is the route to prefer, because the build then owns the compiler
flags, the shared library, the binding module, the cache key, and the packaging
together. A header-only dependency needs no dummy `.c` file:

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

`bridge = true` selects the eligible `static inline` definitions in the named
header. Each entry in `macros` requests one function-like macro and supplies
the type C itself does not provide, and omitting `result` means the wrapper
returns `void`, as `IMAGE_IGNORE` does above. The admitted recipe types are:

| Recipe type | Wrapper C type |
| --- | --- |
| `boolean` | `_Bool` |
| `float` | `float` |
| `number` | `double` |
| `integer` | `int32_t` |
| `int8`, `int16`, `int32`, `int64` | matching signed fixed-width integer |
| `uint8`, `uint16`, `uint32`, `uint64` | matching unsigned fixed-width integer |

Recipes are positional and fixed-arity. The build rejects a missing macro, a
variadic macro, an arity mismatch, or any other type name before installing
a partial binding. A pointer recipe is rejected too, because it would conceal
whether the macro borrows, retains, releases, or writes through the pointer;
use a handwritten C wrapper and an ownership-refined `cdef` for that boundary.

After `nupp build`, the generated module carries the dependency's name:

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
`IMAGE_CLAMP`, so application code uses only the logical names:

```nupp [build/generated/image.nupp]
cdef function __nupp_bridge_fingerprint(value: int32): int32 from "@lib/libimage.so"
local image_triple = __nupp_bridge_fingerprint

return { image_triple = image_triple }
```

The real suffix is a 24-character hexadecimal digest. The leading `@` names the
library relative to the module that loads it rather than to the platform loader
or to where the build ran, which is what makes the output tree relocatable:
copy or move it and the binding still finds its library. A `bindings.library`
override, a `load` naming a library already on the system, and a `pkgConfig`
package are left exactly as written, since none of them travel with the build.

The generated C includes `native/image.h`; it does not copy or translate the
inline body or the macro expansion. The selected C compiler remains the
authority, and changing the header, the macro recipes, the flags, the compiler
identity, or the bridge source invalidates the dependency build.

Every Nupp argument is evaluated before the FFI call. A macro may mention its C
parameter more than once, but it cannot re-evaluate the Nupp expression that
produced the wrapper argument.

### Emit a standalone bridge

`import-c` emits the same inline wrappers without compiling them, which is what
an external build system that owns the native library needs:

```bash
mkdir -p build/generated build/lib src/native

nupp import-c native/image.h \
  --lib build/lib/libimage.so \
  --bridge-out build/generated/image_bridge.c \
  -o src/native/image.nupp

cc -shared -fPIC -I. \
  -o build/lib/libimage.so build/generated/image_bridge.c
```

That compiler command is the Linux form; on macOS use `-dynamiclib` and a
`.dylib` output. In a real build, pass the same include directories,
preprocessor definitions, language standard, target, and required warning flags
as the header's native library. `--bridge-out` handles eligible inline
functions only, so a macro needs either a project dependency or a handwritten
wrapper: its signature belongs in the checked manifest.

The emitted C is deliberately small:

```c [build/generated/image_bridge.c]
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

`--lib` must name the artifact that actually contains the wrappers. The command
writes the requested Nupp and C files and nothing else: it invents no compiler
invocation, creates no library, and arranges no runtime search path.

### Inspect coverage before generating files

Inspection performs preprocessing and declaration analysis but writes no
module, bridge, or native library:

```bash
nupp import-c native/image.h --inspect
# direct 0, bridged 0, skipped 2
```

The JSON result carries totals, warnings, and a disposition for each considered
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

Disposition kinds are stable integration data:

| Kind | Meaning |
| --- | --- |
| `direct` | An externally visible C function is bound directly |
| `type-only` | An aggregate declaration was imported for use by callables |
| `bridge-inline` | A `static inline` definition received a wrapper |
| `bridge-macro` | An explicitly typed function-like macro received a wrapper |
| `skipped` | No safe lowering exists; `reason` says why |

Common skip reasons are `bridge-required`, `parse-failure`,
`unsupported-c-type`, `unsupported-field-type`, `unsupported-bridge-type`, and
`invalid-macro-signature`.

To preview inline bridge eligibility without writing the named bridge, combine
`--bridge-out` with `--inspect`. Inspection still wins over output, while the
flag makes an eligible entry report `bridge-inline` and include its private
`symbol`:

```bash
nupp import-c native/image.h \
  --bridge-out ignored.c --inspect --json
```

### Refine the generated ownership contract

Import and bridge generation infer no lifetime, which is why the generated
module is editable. Refine the declaration once you have reviewed the API
contract, using the modes under [lifetime
behavior](#describe-lifetime-behavior):

```nupp
-- Generated physical type:
cdef function use_context(value: context*?)

-- Reviewed contract: the callee only reads it during this call.
cdef function use_context(borrows value: context*?)
```

For a bridged callable, add the mode to its private generated `cdef function`,
and the logical local alias receives that checked function type. Keep an owned
callback pinned for as long as C may call it. The [JIT callback
hazard](#jit-sensitive-c-boundaries) reaches through a nullable callback field,
parameter, result, array, or pointer nesting as well.

### Bridge and import limits

The direct importer and the bridge refuse a shape for which they do not have
one proven physical meaning:

- C++ declarations, compiler vector extensions, `long double`, `_Complex`,
  inline assembly, and unmodelled calling conventions;
- flexible and variable-length arrays, incomplete by-value aggregates, and
  anonymous-member promotion;
- arbitrary preprocessor programs, variadic macros, pointer-bearing macro
  recipes, and expansions that are not valid in the generated return expression
  or void statement;
- an inline definition whose signature LuaJIT cannot represent, or which is not
  an eligible named `static inline` definition in the selected header.

Direct layout and calling facts are currently host LuaJIT facts. Rich Clang
extraction, ABI witnesses, and complete cross-target bridge emission remain
future work.

## Type the header in place

`cheader` reads a header at compile time and gives you its exports, with no
generated file to keep in step:

```nupp
local mini = cheader("native/mini.h", "mini")

print(mini.mini_add(20, 22))
```

The path must be a literal, or the checker reports it. It is searched
relative to the file, then as written, then against the project roots, and an
unreadable path is reported where it is written. The second argument names a
library to load;
without it the default namespace is used.

This suits a header that changes often, or one you would rather not vendor a
translation of. `import-c` suits a header you want to prune and annotate, since
its output is yours to edit. `cheader` uses the same direct declaration model
for fixed arrays, typedef-named anonymous aggregates, exact pointer nesting,
and callback fields, parameters and results. It never compiles a bridge, so a
header-only callable still needs the manifest dependency or the standalone
`--bridge-out` route above.

## Typed FFI operations

Six FFI operations take a type argument, which is what makes them checked:

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
yields `cdata`, and a string naming an undeclared type is reported.

### C arrays

`carray` allocates a zero-based C array, which is `carray<T>` and distinct from
the one-based Lua array `{T}`:

```nupp
local points = carray(nativePoint, 16)
points[0].x = 1.0
```

`T` must be a reified struct type and the count must be usable as an element
count, or the call is reported.

For a larger or explicitly native-owned array, use the malloc-backed standard
library allocation and give it bounds immediately:

```nupp
local heap = require("nupp.mem.heap")

local values = heap.allocate(ffi.typeof<int32>(), 1000000)
local writable = values:write()
writable[1] = 42 as int32
drop writable
```

## C unions and bitfields

`cdef union` shares the same typed field surface as `cdef struct` while emitting
the correct C tag and ABI layout, and a second colon gives an integer field its
C bit width:

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

`size` is a field's own width and `padding` is the alignment gap that follows
it. They are separate because they answer different questions: an `int8` before
a `number` has size 1 and padding 7, and a writer walking bytes needs both.

Every number is this platform's, asked of the FFI when the layout is first
built and cached per ctype afterwards. The `fingerprint` therefore describes one
platform's layout, which is what makes it usable for noticing that saved data no
longer matches what is reading it. Deciding what to do about a mismatch is the
application's job.

A fixed C array is a field like any other, laid out inline:

```nupp
local struct Vertex
    pos: float[3]
    uv: float[2]
    id: int32
end
```

`layoutof` reports `pos` as `float[3]`, twelve bytes wide at offset zero, which
is what makes a vertex attribute descriptor derivable rather than
hand-maintained. `T[?]` is not a field: a struct whose size depends on a count
nobody wrote has no size, so asking for its layout stays an error.

Only a `struct` has a layout. A `record` is a table, so `layoutof` on one is
reported. Nothing is emitted for a struct nothing asks about, because the
lowering happens at the call site: a program that never calls `layoutof`
carries none of this.

::: deepdive
Reifying puts a value where anything that walks a table cannot reach it.
`string.buffer.encode` refuses cdata outright, `pairs` needs a `__pairs`, and
`type` answers `"cdata"`. Publishing the layout is what makes such a value
reachable again without the language choosing a serialization format for
everyone: a codec, a snapshot writer, or a GPU vertex-attribute descriptor is
written against the layout, and the format stays yours.
:::

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
obligation and names what discharges it, and `takes` says `buffer_free`
consumes it. The lexical owner guarantees cleanup across fallthrough, errors,
and structured control flow.

Use `borrows` when C only observes a resource for the duration of a call, and
`exclusive` when the call needs sole access for its duration. Use `retains` and
`releases` for a pointer C stores beyond a call. Do not reach for `unsafe` to
silence a contract error; use it only where the program must state a fact the
checker cannot prove.

See [ownership.md](../ownership/index.md) for the resource workflow these annotations
join, and [the ownership
reference](../ownership/borrowing.md#borrowing-and-pinning) for output
parameters, callbacks, pinning, and raw-pointer escape hatches.

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
`borrows input: span.Span<Item>`, and `count` is supplied from the spans.
Pointers sharing a count must have equal logical lengths. The wrapper checks
that equality before projecting either pointer and calls C exactly once,
including at count zero, so the foreign implementation must not dereference a
mapped pointer whose count is zero.

A const pointer becomes a shared span and a mutable pointer becomes a writable
span. A counted pointer must use `borrows`, and a count currently uses plain
`uint64`. Strides, byte counts, capacities, prefixes, sentinel termination,
output pointers, and retained pointers require handwritten `ref()` wrappers. See
[](nupp.mem.span) for construction, slicing, partitioning, and shared-range
validation.

## Export ordinary structs to C

Define an ordinary reified struct once in Nupp, then select it and any typed C
entry points that use it:

```bash
nupp export-c -o game.h src/game.nupp game.Position game.integrate
```

The command emits a deterministic, include-guarded C header. Each ordinary
struct receives a collision-safe module-qualified typedef, a semantic and
target-layout fingerprint, and static assertions for its size, alignment, and
every field offset. An embedded struct is ordered by value, and a
pointer-recursive type uses a forward declaration. The configured target's
`layoutTarget` is the authority, so generation never guesses from the build
host and never invokes a C compiler.

An ordinary struct may appear behind a pointer or an array in a
`cdef function`:

```nupp
module game

export struct Position
    x: float
    y: float
end

cdef function integrate(exclusive position: Position*, dt: float)
```

The emitted prototype stays typed. LuaJIT internally receives a compiler-owned
`void *` physical slot, because Nupp's sole runtime representation remains the
existing anonymous ctype, while source checking, ownership, constness, counted
relationships, and the external C definition all retain the ordinary struct
type. An ordinary struct does not cross this boundary by value. `export-c` is
the only publisher: there is no annotation, no user-selected C tag, and no
parallel header generator.

## JIT-sensitive C boundaries

C-derived callback positions are tracked semantically through declarations and
aliases. Passing a Lua function into one reports `jit-callback`, and a variadic
C call reports `jit-boundary`. Disable the callback or the containing cold
function with `jit.off` when the boundary is intentional. Annotating a function
with `@jit` turns either hazard into a non-suppressible contract error.

A third hazard is not about C at all: LuaJIT cannot record the bytecode that
builds a function, so a loop containing one never compiles. `@jit` reports that
as the same contract error, and `jit.off` on the enclosing function silences it
the same way. Outside `@jit` it is `jit-loop-closure`, off until a project asks
for it. See [lints.md](../../../reference/lints.md) for enabling it.

## Build native dependencies reproducibly

For C code that ships with the project, declare a `kind = "c"` dependency in
`nupp.lua` and pin a remote source to an exact revision. Let the build target
depend on it, so headers, generated bindings, native libraries, and Nupp
modules share one cache key and one build graph. See [C
dependencies](../../projects/build.md#c-dependencies) for the provider configuration.

## FAQ

### Does checked C interop replace LuaJIT FFI?

Nupp does not replace LuaJIT FFI or insert a foreign-call runtime. A checked
[`cdef` binding](#hand-write-a-small-binding) lowers to `ffi.cdef`, a namespace
lookup, and the same native call. The [typed FFI
operations](#typed-ffi-operations) likewise keep their LuaJIT representation
while the checker validates their type arguments.

### Does importing a header capture ownership?

A C declaration says that a value is a pointer, but not whether the caller must
free it, whether the callee retains it, or how long a derived pointer stays
valid. Add those facts under [lifetime
behavior](#describe-lifetime-behavior) after importing a header. See [the
ownership reference](../ownership/borrowing.md#borrowing-and-pinning) for the
borrowing, pinning, retention, and cleanup contracts they name.

### Do ownership contracts change the native ABI?

`affine(T, cleanup)`, `borrows`, `exclusive`, and `countedBy` describe checked
relationships around a call; they add no field and change no C signature. See
[the ownership reference](../ownership/borrowing.md#c-interop) for the affine
pointer's ABI representation, and [counted pointer
adapters](#counted-pointer-adapters) for the span a checked caller sees instead
of the pointer and count.

::: seealso
- [ownership.md](../ownership/index.md) for the resource workflow a C boundary joins
- [](nupp.mem.span) for the views a counted pointer projects
- [build.md](../../projects/build.md#c-dependencies) for C and Cargo dependency provider
  configuration
- [embedding.md](../../projects/embedding.md) for calling Nupp from a C host
- [NEP 8](../../../neps/0008-c-interop-and-embedding.md) for the design record
:::
