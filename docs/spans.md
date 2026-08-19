`nupp.mem.span` gives a C array a rooted, one-based, bounds-checked view. A shared
`Span<T>` reads contiguous elements; a writable span adds exclusive access and
an affine lifetime, so the pointer cannot outlive or overlap its owner.

Use spans at checked boundaries. Direct indexing through a pointer or
variable-length C array remains an `unsafe` operation.

```nupp
local span = require("nupp.mem.span")

const text = "hello"
const bytes = span.fromString(text)
assert(#bytes == 5)
```

## Creating a shared span

`fromCarray(source, count)` borrows a C array and records its logical element
count. `fromString(source)` creates the byte-specialized `ByteSpan`. Both keep
their source rooted for the lifetime of the view.

```nupp
local span = require("nupp.mem.span")

local struct Point
    x: float
    y: float
end

const storage = carray(Point, 4)
const points = span.fromCarray(storage, 4)
assert(#points == 4)
assert(points[1].x == 0)
```

Indexes start at one. `view[index]` raises when the index is outside `1` through
`#view`. `slice(first, last)` includes both endpoints and borrows the parent;
omitting `last` extends through the end. An empty slice uses `first, first - 1`.

The operator surface replaces the former element methods and public count field:

| Former spelling | Current spelling |
| --- | --- |
| `view.count` | `#view` |
| `view:get(index)` | `view[index]` |
| `view:set(index, value)` | `view[index] = value` |
| `view:getMut(index).field` | `view[index].field` |
| `span.range(first, last, ...)` | `indexed.range(first, last, ...)` |

The former spellings are migration errors, not deprecated alternate APIs.

::: tip Nonescaping spans are allocation-free at -O1
When the complete use of an exact standard Span constructor is static and
nonescaping, Nupp keeps its anchor, pointer, offset, count, and capability as
compiler-owned values instead of allocating a wrapper. Constructor validation
and bounds checks still run, and the source remains strongly rooted through the
last access. An escape or opaque call materializes the same checked span.
:::

`fromFixedCarray(source, count)` returns `FixedSpan<T, N>` when the array and
literal count carry the same static `N`. It satisfies `Span<T>`, while
preserving the exact count for checks and generated code.

## Writable spans

`writeCarray` returns the affine alias `Writable<T>`. Its underlying
`WriteSpan<T>` contract is what a function accepting exclusive access names:

```nupp
local span = require("nupp.mem.span")
local indexed = require("nupp.mem.indexed")

local struct Point
    x: float
    y: float
end

local function clear(exclusive points: span.WriteSpan<Point>): nil
    const indexes = indexed.range(1, #points, points)
    for index = indexes.first, indexes.last do
        points[index] = new Point(0, 0)
    end
end

local storage = carray(Point, 4)
with points = span.writeCarray(storage, 4) do
    clear(points)
end
```

Whole-element and direct field assignments write through the checked indexed
place. `shared()` downgrades the writer to a shared view for the returned
view's lifetime.

A writable span is affine because it represents exclusive access rather than
owned memory. Dropping it, explicitly or at scope exit, ends that access; it
does not free or copy the source array. `writeFixedCarray` and
`FixedWritable<T, N>` preserve a static count in the same way as their shared
counterparts.

## Slices and partitions

`WriteSpan.slice(first, last)` creates one affine child writer. The parent
remains blocked until the child is dropped, preventing a write through the
parent from overlapping the slice.

`splitAt(mid)` partitions a writer into audited, non-overlapping left and right
regions. `mid` is the number of elements in the left region, so zero gives an
empty left side and `count` gives an empty right side. Both children retain the
parent as their root.

Use a slice for one subrange and `splitAt` when two disjoint writable regions
must be live together. Unknown indexes and bounds otherwise conservatively
overlap.

## One range for several spans

`indexed.range(first, last, ...)` checks one inclusive range against every
trusted Span or SoA view and returns ordinary `first` and `last` integers:

```nupp
local span = require("nupp.mem.span")
local indexed = require("nupp.mem.indexed")

local struct Value
    n: integer
end

local function dot(
    left: span.Span<Value>,
    right: span.Span<Value>
): integer
    const indexes = indexed.range(1, #left, left, right)
    local total = 0
    for index = indexes.first, indexes.last do
        total = total + left[index].n * right[index].n
    end
    return total
end
```

At least one span is required. Empty ranges use the same `first, first - 1`
convention as slices. The typed borrowed vararg passes each original span
directly and allocates no container or interface wrapper.

When the bounds and spans are const-bound in the same function, the successful
range check proves matching indexed reads and writes non-raising inside
the dominated numeric loop. This proof is part of checking at every optimization
level: it is what permits those calls inside `noraise` code.

[Performance](tooling/performance.md#opt-6-indexed-views) says how that proof is
spent at `-O1`, as direct FFI element access and virtual slices that allocate no
wrapper.

## Passing a span to C

`ref()` returns the rooted pointer and logical count for a handwritten native
wrapper. Shared spans return a `const T[?]`; writable spans require exclusive
access and return `T[?]`. The returned pointer borrows the span, so it cannot
escape independently.

A declarative C binding can use
[`countedBy(count)`](c-interop.md#counted-pointer-adapters) instead. Its checked
call surface accepts spans, verifies shared counts, and projects the physical
pointer/count arguments automatically.

## Diagnostics

- **NUPP2001**: an element, count, or result does not fit the span's declared
  type.
- **NUPP2004**: a requested operation is not present on the shared or writable
  view being used.
- **NUPP2602**: an ownership or exclusive-access operation is invalid for the
  live span regions.
- **NUPP2604**: raw pointer arithmetic, indexing, or a region assertion lacks
  the required proof or `unsafe` boundary.

## Next

- [C interop](c-interop.md) maps checked spans onto pointer/count parameters.
- [Ownership](ownership.md) explains the affine and borrowing rules enforced
  by writable views.
- [Structure-of-arrays storage](soa.md) projects struct columns as spans.
