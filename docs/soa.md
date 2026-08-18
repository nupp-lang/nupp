# Structure-of-arrays storage

`nupp.soa` stores every top-level field of a reified struct in its own
contiguous column. Code still reads and writes ordinary struct fields, while the
container provides the column layout needed by data-oriented loops.

```nupp:playground
local soa = require("nupp.soa")
local ffi = require("ffi")

local struct Position
    x: float
    velocity: float
end

local positions = soa.allocate(ffi.typeof<Position>(), 128)
with rows = positions:write() do
    for index = 1, #rows do
        rows[index].x += rows[index].velocity
    end
end
```

## Containers select the layout

A struct keeps its ordinary C-compatible array-of-structures layout. Only an
`soa.Array<T>` splits its fields, so the same `T` can be used as an ordinary
value, passed through [C interop](c-interop.md), or stored in either layout.

```text
Position[3]                 soa.Array<Position>(3)

[x0 velocity0]              x         [x0  x1  x2]
[x1 velocity1]              velocity  [v0  v1  v2]
[x2 velocity2]
```

The container splits top-level fields only. A nested struct or fixed array is
one column whose element has that field's declared C layout. This keeps struct
identity, construction, `layoutof(T)`, and FFI calls independent of the storage
choice.

```nupp
local struct Sample
    position: Position
    history: float[3]
end

local layout = soa.layoutof(ffi.typeof<Sample>())
assert(#layout.fields == 2)
assert(layout.fields[1].name == "position")
assert(layout.fields[2].name == "history")
```

## Owners and row views

`soa.allocate` returns an
[affine owner](ownership.md#declaring-affine-types) of one aligned native slab.
Its lexical scope closes the allocation. `read()` borrows a shared row view,
while `write()` borrows an exclusive affine view.

```nupp
local struct Particle
    x: float
    y: float
    dx: float
    dy: float
end

local particles = soa.allocate(ffi.typeof<Particle>(), 2)
with rows = particles:write() do
    rows[1] = new Particle(1, 2, 3, 4)
    rows[2].x = 10
    rows[2].y = 20
end

local rows = particles:read()
local first: Particle = rows[1]
print(first.x, rows[2].y)
```

Indexing a row supports direct field reads, writes, and compound assignments.
Reading or writing the whole row gathers from or scatters to every column.
Whole-row operations preserve value semantics: changing a gathered `Particle`
does not mutate its source.

Ending the `with` scope or explicitly using `drop` on an ordinary writable view
ends the exclusive borrow; it does not flush or copy data. Stores already wrote
the columns. Both forms use automatic
[lexical destruction](ownership.md#consumption-and-lexical-destruction).

A shared view rejects both direct field stores and whole-row stores. The
exclusive borrow also prevents another access to the owner until it ends.

```nupp
local shared = particles:read()
shared[1].x = 4
```

```text
NUPP2009: SoA shared rows are read-only
```

::: tip Nonescaping row views are allocation-free at -O1
When the complete use of `read()` or `write()` is static and nonescaping, Nupp
keeps the slab anchor, columns, offset, count, and capability as compiler-owned
values instead of allocating a row-view wrapper. Acquisition effects still run
once, the slab remains rooted, and an escape or opaque call materializes the same
checked view.
:::

## Field spans

`field("name")` projects one resolved field as a normal typed
[`nupp.span`](spans.md) view. A shared row view
returns `span.Span<Field>`, and an exclusive row view returns
`span.Writable<Field>`.

```nupp
local span = require("nupp.span")

with
    rows = particles:write(),
    xs: span.WriteSpan<float> = rows:field("x"),
    ys: span.WriteSpan<float> = rows:field("y")
do
    xs[1] = 3.5
    ys[1] = 4.5
end

local xs: span.Span<float> = particles:read():field("x")
print(xs[1])
```

The field name must be a string literal that resolves to a stored field. That
lets the checker assign the exact element type and field identity; a dynamic
string or missing field reports `NUPP2403`.

## Slices

Row slices preserve the column layout and adjust the logical row offset. Their
indexes start at one, like the parent view.

```nupp
local samples = soa.allocate(ffi.typeof<Position>(), 3)
with rows = samples:write() do
    with middle = rows:slice(2, 2) do
        middle[1].x = 12.5
    end
end

local tail = samples:read():slice(2, 3)
assert(#tail == 2)
assert(tail[1].x == 12.5)
```

`slice(first, last)` includes both endpoints. Omitting `last` extends the slice
through the end of the view. Invalid ranges raise before a slice is created.
With `-O1`, nonescaping const slices used only by proved indexed operations can
be scalar-replaced: generated code retains the checked bounds and composed
column offset but creates no row-view wrapper. The same lowering can erase a
nonescaping writable-to-shared downgrade and a statically resolved `field`
projection. Any unsupported or escaping use materializes the safe view normally.
Directly called, nonrecursive local functions in the same module can transport
the virtual row view; exported, recursive, dynamic, foreign, and cross-module
boundaries retain the materialized ABI.

## Field-wise row copies

`copyFrom` moves a row range without materializing row structs. It validates
both ranges before moving bytes, then performs one contiguous copy per field.

```nupp
local source = soa.allocate(ffi.typeof<Particle>(), 2)
local target = soa.allocate(ffi.typeof<Particle>(), 4)

with rows = source:write() do
    rows[1] = new Particle(1, 2, 3, 4)
    rows[2] = new Particle(5, 6, 7, 8)
end

with rows = target:write() do
    rows:copyFrom(2, source:read(), 1, 2)
end

assert(target:read()[3].dy == 8)
```

The generic element type requires source and destination to have the same
struct schema. This operation is the primitive an ECS store can use for growth,
movement, and same-schema restoration.

## Layout reflection

Runtime layout reflection describes the native slab without exposing its
pointer. `soa.layoutof` gives declaration-order fields, stable semantic
identities, C spellings, sizes, alignments, and a versioned fingerprint.
`forCount` adds the offsets and byte counts for one row count.

```nupp
local layout = soa.layoutof(ffi.typeof<Particle>())
local instance = layout:forCount(1024)

for ordinal, field in ipairs(layout.fields) do
    local segment = instance.segments[ordinal]
    print(field.identity, segment.offset, segment.byteCount)
end

assert(layout.fingerprint:match("^soa1|"))
assert(instance.count == 1024)
```

Compile-time [reflection](concepts/reflection.md) publishes the semantic half
of the same description. It reports eligibility and each field's identity,
ordinal, type-graph edge, and C spelling without choosing a target row count.

```nupp
local firstIdentity = comptime do
    local info = nupp.reflect(Particle)
    assert(info.soa.eligible)
    return info.soa.fields[1].identity
end

print(firstIdentity)
```

Use semantic reflection to generate storage and snapshot adapters. Use runtime
layout reflection when allocation sizes, alignment, or the storage fingerprint
matter on the selected target.

## Hot loops and AOT functions

The canonical loop `for index = 1, #rows` proves every indexed row access
is in bounds. Nupp lowers fields inside that loop to direct typed-column loads
and stores using the view offset. An arbitrary index keeps its runtime bounds
check.

No profiler call is injected into the loop. `nupp bc --check FILE` inspects the
lowered bytecode without executing it; see
[LuaJIT trace checking](tooling/jit-trace-checking.md) for the complete trace
contract.

An [`@aot`](tooling/aot.md) function retains the same resolved field identities
and single-map-loop fact. A borrowed kernel names the writable capability
intersection rather than the affine owner alias:

```nupp
@aot
local function advance(
    exclusive rows: soa.WriteToken & soa.WriteSpan<Particle>,
    delta: float
): nil
    for index = 1, #rows do
        rows[index].x += rows[index].dx * delta
        rows[index].y += rows[index].dy * delta
    end
end
```

The AOT backend retains those field identities and unit strides in its IR for
direct scalar or lane lowering. `nupp aot` can display the lowered artifacts;
`nupp build` still emits the ordinary Lua body until object integration is
wired into production builds.

## Snapshots and ECS storage

`nupp.soa` supplies storage mechanics, not a general storage interface or a
snapshot format. An ECS remains responsible for capacity, archetype movement,
dirty state, component policy, and schema migration.

A snapshot adapter can pair `Array.fingerprint` and `Array.count` with one
length-validated subframe per reflected field. It must not serialize the raw
slab as one opaque buffer: alignment padding and target layout are part of the
runtime representation rather than the semantic component schema.

Changing a stored struct's fields or layout requires a
[hot-reload restart](tooling/hot-reload.md#changes-that-require-restart) before
existing storage can be reached. Nupp does not reinterpret or implicitly
migrate a live owner.

## Limits

The first SoA representation accepts reified structs whose top-level fields
have fixed C storage. It does not accept records, unions, interfaces,
GC-managed fields, owned fields, borrowed fields, or variable-size fields.

The container does not expose column pointers, byte offsets, or a `void **`
descriptor to checked code. Field spans provide typed contiguous access when a
system needs one column directly.

## Diagnostics

- **NUPP2009**: code writes through a shared SoA row view.
- **NUPP2403**: an allocation element is not SoA-eligible, or `field` does not
  name one resolved stored field.

## Next

- [records.md](type-system/records.md): the value and C layout rules that SoA
  containers leave unchanged.
- [ownership.md](ownership.md): the owner and borrow rules enforced by row and
  field views.
- [reflection.md](concepts/reflection.md): generating adapters from semantic
  type information.
