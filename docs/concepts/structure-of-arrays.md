# Structure-of-arrays storage

`nupp.mem.soa` stores every top-level field of a reified struct in its own
contiguous column. Reach for it when a loop walks one or two fields of many
rows and the ordinary array-of-structures layout brings the rest along.

```nupp:playground
local soa = require("nupp.mem.soa")
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
`soa.Array<T>` splits its fields, so the same `T` can be an ordinary value,
passed through [C interop](c-interop.md), or stored in either layout.

```text
Position[3]                 soa.Array<Position>(3)

[x0 velocity0]              x         [x0  x1  x2]
[x1 velocity1]              velocity  [v0  v1  v2]
[x2 velocity2]
```

::: deepdive
The container owns the layout rather than the declaration, because one
declaration needs both: a value passed to C wants the canonical layout, and a
large array wants its columns contiguous. Annotating the declaration would make
one nominal identity cover two incompatible physical meanings, so a value's
memory layout would depend invisibly on where the value came from.

See [NEP 10](../neps/0010-structure-of-arrays.md) for more information.
:::

### Nested fields stay whole

The container splits top-level fields only. A nested struct or fixed array is
one column whose element keeps that field's declared C layout, which is what
holds struct identity, construction, `layoutof(T)`, and FFI calls independent
of the storage choice.

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

`soa.allocate` returns an [affine
owner](../type-system/ownership.md#declaring-affine-types) of one aligned
native slab, and its lexical scope closes the allocation. `read()` borrows a
shared row view; `write()` borrows an exclusive affine one.

### Row access

Indexing a row supports direct field reads, writes, and compound assignments.
Reading or writing a whole row gathers from or scatters to every column.

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

A whole-row operation preserves value semantics: changing a gathered `Particle`
does not mutate the row it came from.

### Ending an exclusive borrow

Leaving the `with` scope ends the exclusive borrow, and `drop` on an ordinary
writable view ends it early. Neither flushes or copies anything, because the
stores already wrote the columns. Both forms use automatic [lexical
destruction](../type-system/ownership.md#consumption-and-lexical-destruction).

### Shared rows reject writes

A shared view rejects direct field stores and whole-row stores alike, and the
exclusive borrow prevents any other access to the owner until it ends.

```nupp
local shared = particles:read()
shared[1].x = 4
```

```text
NUPP2009: SoA shared rows are read-only
```

## Field spans

`field("name")` projects one resolved field as a normal typed
[`nupp.mem.span`](../modules/nupp/mem/span.md) view. A shared row view returns
`span.Span<Field>`, and an exclusive row view returns `span.Writable<Field>`.

```nupp
local span = require("nupp.mem.span")

with
    rows = particles:write(),
    xs: span.Writable<float> = rows:field("x"),
    ys: span.Writable<float> = rows:field("y")
do
    xs[1] = 3.5
    ys[1] = 4.5
end

local xs: span.Span<float> = particles:read():field("x")
print(xs[1])
```

The field name must be a string literal that resolves to a stored field, which
is what lets the checker assign the exact element type and field identity. A
dynamic string or a missing field is reported.

## Slices

A row slice preserves the column layout and adjusts the logical row offset. Its
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

`slice(first, last)` includes both endpoints, and omitting `last` extends the
slice through the end of the view. An invalid range raises before a slice is
created.

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

The generic element type requires source and destination to share one struct
schema. This operation is the primitive an ECS store uses for growth, movement,
and same-schema restoration.

## Layout reflection

Two descriptions of the same storage are available: one at run time, which
knows the target's sizes and offsets, and one at compile time, which knows the
field identities.

### Runtime layout

`soa.layoutof` gives declaration-order fields, stable semantic identities, C
type names, sizes, alignments, and a versioned fingerprint, without exposing the
slab pointer. `forCount` adds the offsets and byte counts for one row count.

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

### Comptime reflection

Compile-time [reflection](reflection.md) publishes the semantic half of the
same description. It reports eligibility and each field's identity, ordinal,
type-graph edge, and C type name, without choosing a target row count.

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

## Hot loops

The canonical loop proves every indexed row access is in bounds, so it lowers
to direct typed-column loads and stores. An arbitrary index keeps its runtime
bounds check.

```nupp
with rows = particles:write() do
    for index = 1, #rows do
        rows[index].x += rows[index].dx
    end
end
```

See [`OPT-6`](../guides/performance.md#opt-6-indexed-views) for how that proof
lowers, and [ahead-of-time.md](../guides/ahead-of-time.md) for what an `@aot`
kernel retains.

### Row views without a wrapper

At `-O1`, a row view whose complete use is static and nonescaping is
scalar-replaced: the slab anchor, columns, offset, count, and capability become
compiler-owned values instead of an allocated wrapper. Acquisition effects
still run once and the slab stays rooted.

The same lowering covers a nonescaping const slice used only by proved indexed
operations, a nonescaping writable-to-shared downgrade, and a statically
resolved `field` projection. A directly called, nonrecursive local function in
the same module can transport the virtual view. An escape, an opaque call, an
export, recursion, and a dynamic, foreign, or cross-module boundary materialize
the same checked view instead.

## Snapshots and ECS storage

`nupp.mem.soa` supplies storage mechanics, not a general storage interface or a
snapshot format. An ECS remains responsible for capacity, archetype movement,
dirty state, component policy, and schema migration.

A snapshot adapter can pair `Array.fingerprint` and `Array.count` with one
length-validated subframe per reflected field. It must not serialize the raw
slab as one opaque buffer: alignment padding and target layout are part of the
runtime representation rather than the semantic component schema.

Changing a stored struct's fields or layout requires a [hot-reload
restart](../guides/hot-reload.md#changes-that-require-restart) before existing
storage can be reached. Nupp does not reinterpret or implicitly migrate a live
owner.

## Limits

The first SoA representation accepts a reified struct whose top-level fields
have fixed C storage. It accepts no records, unions, interfaces, GC-managed
fields, owned fields, borrowed fields, or variable-size fields.

The container exposes no column pointer, byte offset, or `void **` descriptor
to checked code. Field spans provide typed contiguous access when a system
needs one column directly.

## FAQ

### Does SoA storage change a struct's C layout?

No. The container selects the layout, so `Position` passed to C keeps its
canonical field order and `soa.Array<Position>` splits the same declaration
into columns. See [Containers select the
layout](#containers-select-the-layout) for the two layouts side by side.

### How does a column reach a C function?

Project it with `field("name")` and pass the resulting span, which is the only
typed contiguous handle on a column. The container itself never yields a column
pointer. See [span.md](../modules/nupp/mem/span.md) for the span operations a C
boundary uses.

### Can a record be stored in an SoA array?

No. A record is a table, so it has no fixed C storage to split into columns,
and `soa.allocate` reports one. Store a reified `struct`
instead, and see [Limits](#limits) for the other field types the container
refuses.

::: seealso
- [span.md](../modules/nupp/mem/span.md) for the views `field` projects
- [performance.md](../guides/performance.md#opt-6-indexed-views) for the
  indexed-view lowering
- [reflection.md](reflection.md) for the comptime description of a struct
- [NEP 10](../neps/0010-structure-of-arrays.md) for the design record
:::
