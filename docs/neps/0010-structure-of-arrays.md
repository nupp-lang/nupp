---
title: Structure-of-arrays storage
status: Implemented
created: 2026-08-19
---

## Summary

An explicit container family stores the top-level fields of a reified struct in
separate contiguous columns. The struct keeps its array-of-structures layout and
value semantics: column storage is a property of a *container*, not a modifier
that changes what the struct means everywhere. Direct indexed field expressions
keep their ordinary spelling, and the two view types are deliberately not
interchangeable.

See [structure-of-arrays.md](../concepts/structure-of-arrays.md) for allocating
and reading a column container.

## Goals

- Make column-major storage available without changing the type of the values
  stored in it.
- Keep the reading and writing syntax identical to the row-major case.
- Make the choice local, visible in the type, and impossible to erase by a cast.

## Non-goals

- A layout modifier on the declaration.
- Reinterpreting live bytes across a layout change.

## Motivation

### Declarations need both layouts

The same struct value passed to C, returned from a function, or stored alone
wants the canonical layout. A large simulation array wants its columns
contiguous. Both are correct uses of one declaration.

Putting the choice on the declaration forces one answer on both uses and makes
the declaration's nominal identity hide two incompatible physical meanings. A
value's memory layout would then depend, invisibly, on where it came from.

### Syntax has to stay ordinary

Column storage is worth having only if the code that uses it reads like the code
that does not. A separate access syntax would make switching layouts a rewrite,
which defeats the purpose of being able to choose.

## Overview and specification

### Syntax

Column storage is a container, not a modifier on the declaration:

```nupp
local soa = require("nupp.soa")
local heap = require("nupp.mem.heap")

local rowMajor = heap.allocate(ffi.typeof<Particle>(), count)
local columns  = soa.allocate(ffi.typeof<Particle>(), count)
```

### Worked example

Both load and store ordinary values, and the loop body is identical:

```nupp
local struct Particle
    x: float
    y: float
    dx: float
    dy: float
end

with rows = columns:write() do
    for i = 1, rows.count do
        rows[i].x = rows[i].x + rows[i].dx * delta
        rows[i].y = rows[i].y + rows[i].dy * delta
    end
end
```

The two view types are not interchangeable. One promises contiguous objects and
the other promises contiguous fields, and no cast or structural match erases the
difference:

```nupp
local function kernel(view: span.Span<Particle>) ... end

kernel(columns:read())    -- rejected: soa.Span<Particle> is not span.Span<Particle>
```

### Lowering

Row-major storage is one contiguous block of struct values:

```text
[x y dx dy][x y dx dy][x y dx dy] ...
```

Column storage is one slab with a column per top-level field:

```text
[x x x ...][y y y ...][dx dx dx ...][dy dy dy ...]
```

An indexed field expression addresses the column and the row rather than the
element and the offset, so no row proxy is allocated:

```lua
-- rows[i].x = rows[i].x + rows[i].dx * delta
local __x, __dx = rows.__col_x, rows.__col_dx
__x[i - 1] = __x[i - 1] + __dx[i - 1] * delta
```

The struct itself is unchanged: passed to C, returned, or stored alone, a
`Particle` has its canonical layout.

### Containers own the choice

A container owns the layout choice, and non-interchangeable views are what make
that choice mean something. Two things with the same element type and different
physical meaning must not be substitutable, or the guarantee is decorative and a
caller that assumed the wrong one gets plausible garbage rather than a
diagnostic.

### Layout changes are schema changes

Changing a container from row-major to column-major is a storage-schema change
even though the value type is unchanged. Hot reload must restart or invoke an
application-owned migration rather than reinterpret live bytes.

Stating that is what keeps a layout change from being silently unsafe. The value
type is identical, so nothing else in the system would notice. See
[NEP 6](0006-hot-reload.md) for more information.

### Pooled element storage

**Not built, and blocked.** A struct is its C layout, which is why the
compiler's own hottest data cannot be one: a token is six numbers, twenty-three
flags, two strings, and a dozen sparse references, and the numbers are the
smallest part of it. Instances would come from a pool owning the block they live
in, with fields packed into an implicit word, computed on read, or held beside
the instance.

The blocker is measured. An element reference does not keep its block alive:

```lua
local held
do
  local block = ffi.new("Tok[?]", 64)
  block[7].offset = 1007
  held = block[7]
end
collectgarbage("collect")            -- block is unreachable; held is not
print(held.offset)                   --> 0, from reused memory
```

That is not a crash. It is a read of reused memory returning a plausible value,
and chunking fixes reallocation while doing nothing about this.

Three ways out, none good. A strong registry makes element validity equal pool
liveness, which is the ownership model applied at the pool rather than the
element, but use after release stays undefined and unchecked, so element access
becomes an unsafe operation wearing a typed field's clothes. A reference
carrying its anchor measured at 217 bytes a token against the table's 264,
because boxing an eight-byte value as cdata costs about 200. Leaving tokens as
tables saves nothing.

The third way out is a lifetime system rather than a stage. It would have to
prove that every structure storing an element also retains its pool, through
locals, returns, closures, nested nodes, calls, unions, and containers mixing
pools.

**And the trade has moved.** The pooled design saves 3.6x on lexing allocation,
which is 38% of what a build allocates. But the collector is 3% to 5% of build
time, where the trace compiler is about half, and the escape analysis other
optimizations already want attacks that half at no new unsafety. The packed
booleans and read-computed fields are unaffected and worth building alone.

## Risks and assumptions

- **The performance benefit depends on the access pattern, and nothing checks
  it.** Column storage for a workload that reads whole rows is a pessimization,
  and the type system cannot tell.
- **Two view types is a real surface cost.** Every API that takes a view must
  decide which one, or be generic over both, and the non-interchangeability that
  makes the design sound is what makes that unavoidable.
- **Only top-level fields are columns.** Nesting has to resolve to something,
  and the current answer constrains what a struct in a column container can
  usefully contain.
- **The migration requirement is a convention.** Nothing prevents an application
  from reinterpreting bytes across a layout change; the design can only say that
  it must not.

## Alternatives considered

**A layout annotation on the declaration.** Rejected: it forces one answer on
every use of the type and makes one nominal identity cover two incompatible
physical layouts. A value's memory layout would then depend on its declaration
rather than on where it is stored.

**A distinct element type for column storage**, making a column-stored particle
a different type from a particle. Rejected: it propagates through every
signature that touches one, and the value semantics genuinely are the same.

**Interchangeable views**, with the layout as an implementation detail behind a
common interface. Rejected: the promises are different, contiguous objects
against contiguous fields, and code that assumes the wrong one is wrong in a way
that produces plausible garbage.

**A separate access syntax for columns.** Rejected: switching layouts would
become a rewrite, which removes the reason to make the choice local.

**Reinterpreting live storage across a layout change** during hot reload.
Rejected: the value type is unchanged, so nothing else would notice the
reinterpretation was invalid.
