# Semantic reflection

`nupp.reflect(T)` resolves a type and hands comptime an immutable descriptor of
what it means. Code generated from that descriptor is written once and stays
correct as the declaration changes, because it is derived from the declaration
rather than maintained beside it.

```nupp:playground
local m = {}

local record Position
    x: number
    y: number
end

const PositionCodec: nupp.fieldcodec.KeyedCodec<Position> = comptime do
    return nupp.fieldcodec.compile(nupp.reflect(Position))
end

function m.encode(position: Position): {[string]: any}
    return PositionCodec:encode(position)
end

return m
```

Adding a field to `Position` changes what `encode` writes. Nothing else changes.

## Descriptors are graphs, not trees

A type can refer to itself, so schema 2 represents it as an acyclic indexed
graph: `root` selects a node in `types`, and edges between nodes are integer
indices into the same array.

The graph covers nominal records, interfaces and structs; shapes, fields and
indexers; function signatures and packs; generic arguments; unions and
intersections; ownership wrappers; and arrays, pointers and C types. The root's
common members are also reachable directly as `kind`, `name`, `fields`,
`annotations` and `fingerprint`.

## Annotations travel with the descriptor

Checked typed annotations on declarations and fields appear as ordered
`annotations`, and an `@ref` argument is an edge into the same `types` graph.
Annotation names, arguments, values and referenced types all participate in the
fingerprint, so a generator can dispatch on them and a change to one is a change
to the descriptor.

## Comptime may read, not mutate

User comptime code reads descriptor members, uses `#`, and traverses arrays with
deterministic `ipairs` or `pairs`. Views preserve identity for equality, reject
mutation, and cannot escape as runtime tables.

## Meaning is not layout

Reflection reads declared meaning. `nupp.sizeof`, `nupp.alignof` and
`nupp.offsetof` answer the build's `layoutTarget` instead, and `layoutof`
reports how a struct is laid out in C memory.

The fingerprint follows from the canonical semantic graph rather than from the
checker's process-local type identities, so it is stable across runs and across
machines.

## Diagnostics

- **NUPP2414**: a descriptor or other opaque result reached a binding that
  cannot materialize it.
- **NUPP2415**: a declared type has no registered materialization for the
  result, or a worker payload failed the provider's schema and fingerprint
  checks.
- **NUPP2416** / **NUPP2418**: the provider rejected the request.

## Next

- [Comptime](comptime.md): the block a descriptor is read inside, and what may
  come back out of one.
- [Calling C safely](../c-interop.md): `layoutof`, which answers the layout
  question this one deliberately does not.
