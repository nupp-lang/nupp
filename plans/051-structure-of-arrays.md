# Structure-of-arrays storage

Status: Nupp core implemented through S3; the trace gate passes. Direct AOT backend
consumption and the external Tecs snapshot/derive port remain follow-up integration.

## Implementation findings

The core implementation landed as `nupp.soa` with compiler-recognized
`allocate`, `layoutof`, row places, and resolved field projection. The owning array
uses one over-aligned native slab and keeps the original allocation for cleanup. A
shared view is freely borrowable; a writable view is the affine intersection of a
non-generic write token and `WriteSpan<T>`. Keeping those responsibilities disjoint
avoids making the general generic-supertype cache responsible for an ownership
terminal.

No general storage interface is needed in Nupp. `soa.Array<T>` is the concrete owner,
and Tecs remains responsible for capacity, archetype movement, dirty state, and
storage policy. The core now exposes `WriteSpan<T>:copyFrom(...)`: it checks both
ranges before moving data and performs one contiguous `ffi.copy` per field. That is
the primitive a Tecs SoA store needs for growth, swap/movement, and same-schema
restore without materializing rows.

SoA columns have two reflection layers:

- `nupp.reflect(T).soa` publishes eligibility plus ordered semantic field identities,
  ordinals, resolved type graph indexes, and C spellings for derives and tooling.
- `soa.layoutof(ffi.typeof<T>())` adds target sizes, alignments, count-dependent
  offsets, byte counts, and the versioned storage fingerprint. A live owner publishes
  the same fingerprint and count without exposing a pointer.

Nested structs and fixed arrays remain one top-level column. The layout helper must
reconstruct their declared ctypes rather than use `typeof(sample.field)`: LuaJIT
returns a reference ctype for field access, and a reference cannot form the typed
column pointer.

The canonical hot loop `for i = 1, rows.count` is also the bounds proof. Its body emits
direct numeric column loads/stores using the view's slice offset; arbitrary indexes
retain `checkedIndex`, and complex receivers retain a once-only expression wrapper.
This needs no injected profiling code. `nupp bc --check` verifies traceability, while
`bench/soa.nupp` permanently compares the lowered form with hand-written cdata. One
representative traced run measured 3.13 ms generated versus 3.03 ms hand-written
(1.033x, inside the ten-percent gate); the interpreter measured 539.93 ms versus
934.96 ms.

Checked AOT bodies retain the same semantic `soaField` identity and single-map-loop
fact. The current AOT work in this repository is still an IR/backend spike rather
than an end-to-end compiler path, so turning those facts into direct scalar and lane
C remains S4 rather than being simulated in the Lua lowering.

Hot reload already restarts for a changed struct/storage declaration before a patch
can reinterpret an existing owner, and a dedicated regression test holds that
boundary. There is no implicit migration.

Tecs snapshots remain compatible by adapter, not by pretending the slab is AoS. The
implemented reflection and field-wise copy cover the Nupp side. Tecs must still add
`COLUMN_SOA`, snapshot version 2, one length-validated subframe per reflected field,
and its application migration policies in the Tecs repository; that code is not
part of this repository.

## Decision

Add an explicit `nupp.soa` container family for storing the top-level fields of a
reified struct in separate contiguous columns. The struct keeps its existing
array-of-structures layout and value semantics; SoA is a property of a container,
not a modifier that changes what the struct means everywhere.

Direct indexed field expressions retain their ordinary spelling:

```nupp
local soa = require("nupp.soa")
local ffi = require("ffi")

struct Particle
    x: float
    y: float
    dx: float
    dy: float
end

local particles = soa.allocate(ffi.typeof<Particle>(), count)
local rows = particles:write()

for i = 1, rows.count do
    rows[i].x = rows[i].x + rows[i].dx * delta
    rows[i].y = rows[i].y + rows[i].dy * delta
end
```

The storage is logically:

```text
Particle[3]                 soa.Array<Particle>(3)

[x0 y0 dx0 dy0]             x  [x0  x1  x2]
[x1 y1 dx1 dy1]             y  [y0  y1  y2]
[x2 y2 dx2 dy2]             dx [dx0 dx1 dx2]
                             dy [dy0 dy1 dy2]
```

The checker resolves `rows[i].x` as the place `(rows, field Particle.x, index
i)`. Generated Lua addresses the `x` column at `i`; AOT IR receives the same
field identity, base, count, and unit stride. No row proxy, metamethod, closure,
or per-access allocation exists at runtime.

The representation is deliberately visible in the container type. Code chooses
`heap.Array<Particle>` for AoS and `soa.Array<Particle>` for SoA. Nupp does not
silently promote an ordinary array, annotate `Particle` itself as SoA, or make
`type`, `pairs`, FFI, serialization, and pointer behavior change because an
optimizer guessed a layout.

## Goal

Make field-column storage pleasant enough to use as ordinary typed data while
retaining the properties for which it was chosen:

- one contiguous fixed-width array per top-level field;
- ordinary `rows[i].field` reads, writes, and compound assignments;
- whole-row load and store when a value really is needed;
- safe shared and exclusive field-column spans;
- direct AOT lane loads and stores without gathers or strided public views;
- one owned allocation whose count and lifetime cannot separate from its columns;
- generated layout, snapshot, and ECS adapters built from semantic field identity.

Tecs is the acceptance workload. Its archetypes already store one column per
component; a hot FFI component is still an AoS column internally. `Transform2D`,
particles, bounds, and similar components should be able to select a SoA backing
without making systems hand-spell `xs[i]`, `ys[i]`, and four parallel lengths.

## Non-goals

- Do not change the ABI, `layoutof`, `ffi.typeof`, construction, or value semantics
  of the element struct.
- Do not convert ordinary arrays or struct fields to SoA as an optimization.
- Do not make table records, arbitrary shapes, interfaces, unions, owned fields,
  borrowed fields, variable-size fields, or GC-managed values SoA-storable in the
  first release.
- Do not recursively split nested structs or fixed arrays. Each top-level field is
  one column whose element is that field's declared storage type.
- Do not expose byte offsets, alignment arithmetic, raw column pointers, or a raw
  `void **` descriptor in checked code.
- Do not add a general row-reference or lvalue-alias language in this plan.
- Do not define an ECS, snapshot format, schema migration system, or component
  annotation in the Nupp standard library.
- Do not add AoSoA blocking until a measured workload beats plain SoA after AOT
  lane lowering.
- Do not claim SoA is faster for every workload. Whole-row C calls, bulk AoS copies,
  and code consuming most fields together may be better left AoS.

## Why the container owns the choice

One declaration may need both layouts. A `Particle` value passed to C, returned
from a function, or stored alone has the canonical struct layout. A large simulation
array may need its `x` values contiguous. Putting `@soa` on the declaration would
force one answer on both uses and make the declaration's nominal identity hide two
incompatible physical meanings.

The container makes the choice local and type-visible:

```nupp
local aos = heap.allocate(ffi.typeof<Particle>(), count)
local columns = soa.allocate(ffi.typeof<Particle>(), count)
```

Both load and store ordinary `Particle` values. Their views are not interchangeable:
`span.Span<Particle>` promises contiguous `Particle` objects, while
`soa.Span<Particle>` promises contiguous fields. No cast or structural match may
erase that difference.

This is also the compatibility boundary. Changing a Tecs component from AoS to SoA
is a storage-schema change even though the component value type is unchanged. Hot
reload must restart or invoke an application-owned migration rather than reinterpret
live bytes.

## Public value and view model

The initial family mirrors `nupp.heap` and `nupp.span` where their lifetime rules are
the same:

```nupp
record soa.Array<T> is soa.ArrayToken
    readonly count: integer
    read: function(borrows self: Array<T>): soa.Span<T> borrows (self)
    write: function(exclusive self: Array<T>): soa.Writable<T> borrows (self)
    close: nosuspend function(takes self: Array<T>): nil
end

sealed interface soa.Span<T>
    readonly count: integer
    get: function(borrows self: Span<T>, index: integer): T
    field: function<F>(borrows self: Span<T>, name: string): span.Span<F> borrows (self)
end

sealed interface soa.WriteSpan<T> is soa.WriteToken
    readonly count: integer
    get: function(borrows self: WriteSpan<T>, index: integer): T
    set: function(exclusive self: WriteSpan<T>, index: integer, value: T): nil
    field: function<F>(exclusive self: WriteSpan<T>, name: string): span.Writable<F> borrows (self)
    shared: function(borrows self: WriteSpan<T>): soa.Span<T> borrows (self)
    commit: nosuspend function(takes self: WriteSpan<T>): nil
    copyFrom: function(exclusive self: WriteSpan<T>, targetFirst: integer,
        borrows source: soa.Span<T>, sourceFirst: integer, count: integer): nil
end

type soa.Writable<T> = affine(soa.WriteToken & soa.WriteSpan<T>, soa.destroyWriteSpan)
```

These signatures describe the contracts; `field` needs compiler resolution because
its result type comes from the named field. As with the rejected `span.field`
candidate in plan 041, the string is resolved to a semantic field reference, so
rename, references, completion, summaries, and diagnostics use declaration identity
rather than text. Aliasing the standard function preserves its intrinsic identity;
shadowing the name does not gain compiler privilege.

The final spelling may use module functions rather than methods if generic-result
resolution makes that surface clearer. It must still expose exactly one resolved
field operation, not generated named methods plus a reflective fallback.

`soa.allocate(ctype<T>, count)` returns
`affine(soa.Array<T>, soa.destroyArray)`. It rejects a negative count, size overflow,
unsupported element layout, or allocation failure before publishing the owner.
`close` and automatic cleanup release the complete storage once.

Dynamic growth is outside the first owner. A growable ECS store may allocate a larger
owner, copy each field range, and move the replacement into its own storage object.
Add `soa.Vector<T>` only after two independent consumers need one policy for growth,
initialization, movement, and failure.

## Row expression semantics

### Direct reads and writes are places

On a shared or writable view, `rows[i].field` performs one bounds check and one field
column access. A compound assignment evaluates the receiver and index once:

```nupp
rows[next()].x += amount()
```

is semantically equivalent to evaluating `rows`, `next()`, and `amount()` once in
ordinary Nupp order, then loading and storing the same place. Code generation may
share the checked index and column binding; it may not repeat a side effect.

Writing a field requires an exclusive overlapping region. Reading a different fixed
field is compatible with that write when the general capability-region algebra proves
the siblings disjoint. A dynamic field name is never accepted; every projection is a
resolved declaration field.

### Whole rows materialize or scatter

Reading `rows[i]` as a value constructs one ordinary `T` from its columns. That value
has normal struct identity and AoS layout:

```nupp
local snapshot: Particle = rows[i]
consume(snapshot)
```

Mutating `snapshot` mutates the value, not its source. Nupp does not create an
invisible write-back proxy.

Assigning an ordinary value to `rows[i]`, or calling `set`, evaluates the value once
and scatters its top-level fields into the selected row. The complete row is one
logical write for bounds, effects, and error ordering; an implementation may not
leave half a row changed after a check it could have performed before the first store.

The first release does not let `local row = rows:getMut(i)` act as an escaping lvalue
alias. Direct indexed field expressions cover the hot loop without inventing a new
reference kind. A later lexical row view requires an independent design proving it
can be erased through every capture, call, join, and gradual boundary.

### Gradual and foreign boundaries

An `soa.Array<T>` or view may cross `any` as its ordinary opaque runtime object. A
virtual row cannot: there is no row object to box. When the receiver's static type is
unknown, `value[i].x` has ordinary Lua meaning and receives no SoA rewrite.

Passing `rows[i]` to an ordinary `T` parameter materializes a value. C receives that
ordinary struct value only through existing supported FFI rules. Passing a column to
C uses the checked contiguous `span` returned by `field`; no operation projects a
pointer to a fictional contiguous row array.

## Storage representation

The first implementation owns one native slab. The per-element target layout record
already knows each top-level field's C type, size, and alignment. A SoA descriptor
computes one aligned segment per field for `count` elements, checks every multiply and
addition for overflow, and allocates the final byte count once. Zero-count storage
still owns a valid allocation sentinel and publishes zero-length columns.

The slab allocation meets the maximum declared column alignment. Use the platform's
portable aligned-allocation path or checked over-allocation with the original base kept
for cleanup when ordinary `malloc` alignment is insufficient; never weaken a field's
alignment to preserve the one-allocation goal.

The descriptor contains:

- the element's nominal declaration identity and semantic fingerprint;
- a SoA schema version;
- ordered stable field identities and field storage types;
- per-field alignment, element width, segment offset, and count;
- total allocation alignment and byte size; and
- a storage fingerprint independent of the allocated count.

Padding between columns is private. Padding inside a nested field value remains part
of that field's canonical value layout. The descriptor is derived from the selected
target model, never by probing the build host during cross-compilation.

Ordinary generated Lua keeps the owner anchor and a private column table or generated
column bindings. A statically resolved row-field access uses a numeric stable field
slot and typed cdata column; it does not look up a source field string. Before freezing
that representation, measure direct generated bindings, a numeric column table, and a
per-instantiation generated record under LuaJIT. Choose the smallest representation
whose warm trace is the same load/store shape as hand-written parallel cdata arrays.

AOT IR does not inherit the Lua representation. Its boundary receives checked column
bases and one count, then represents `(field identity, index)` directly. A scalar tail
and vector body use the same bounds and alias facts.

## Reflection surface

SoA columns have reflection data at both compile time and run time. Reflection exposes
what the storage contains and how it is laid out; it does not expose a column pointer or
grant read/write capability.

Compile-time semantic reflection is authoritative. `nupp.reflect(T)` and derive recipes
can obtain:

- the element's nominal identity and the SoA storage fingerprint;
- every stored top-level field's stable declaration identity, source name, ordinal,
  resolved storage type, C spelling, width, and alignment;
- whether a declaration member is stored, associated, derived, or ineligible;
- the segment alignment and offset formula for an arbitrary count; and
- typed operations for allocating, projecting, copying, gathering, and scattering that
  field.

This is the surface a Tecs derive uses. It receives semantic type and field handles, not
strings that it reparses and not compiler CST nodes.

Runtime reflection is emitted only when requested, following `layoutof` and plan 044's
on-demand `TypeInfo` model. A representative immutable surface is:

```nupp
record soa.Layout
    readonly name: string
    readonly fingerprint: string
    readonly alignment: integer
    readonly fields: {soa.FieldLayout}
    forCount: function(self: soa.Layout, count: integer): soa.InstanceLayout
end

record soa.FieldLayout
    readonly name: string
    readonly ctype: string
    readonly ordinal: integer
    readonly elementSize: integer
    readonly alignment: integer
end

record soa.SegmentLayout
    readonly field: soa.FieldLayout
    readonly offset: integer
    readonly byteCount: integer
end

record soa.InstanceLayout
    readonly count: integer
    readonly byteSize: integer
    readonly segments: {soa.SegmentLayout}
end
```

`soa.layoutof(T)` returns count-independent field metadata and the storage fingerprint.
`layout:forCount(count)` checks the same arithmetic as allocation and returns the
relative segment offsets and byte counts for that count. A live `soa.Array<T>` reports
the same layout fingerprint and count. The public records may later carry plan 044
`TypeInfo` witnesses beside the stable C spelling; derives do not wait for runtime
reflection to obtain typed handles.

Field declaration identities remain compiler/reflection handles. Persistent formats
store the versioned fingerprint plus field names and type spellings needed for
migration; they do not serialize an internal compiler ID and expect another build to
understand it.

Layout reflection never returns the slab base, typed column pointers, or an operation
that constructs a span from numeric offsets. Checked code obtains data only through the
owner's shared or writable views and resolved field projection. `unsafe` code may use
existing explicit pointer facilities, but reflection data alone manufactures no
provenance.

## Element eligibility

`soa.Array<T>` initially requires a reified nominal struct whose stored top-level
fields all have target-validated, fixed-size, independently addressable C storage.

Allow:

- fixed-width numeric and boolean storage;
- pointers that are already legal unrestricted struct fields;
- nested reified structs as one unsplit field column; and
- fixed C arrays as one unsplit field column.

Reject:

- records, interfaces, functions, threads, strings, tables, `any`, and variable-size
  arrays;
- affine, transfer-only, borrowed, pinned, retained, or cleanup-bearing fields;
- associated fields and derived fields as storage columns;
- bitfields or overlapping union storage; and
- a target layout whose field alignment or width is unknown.

Plan 040's `flag` fields may become eligible after their final physical bitset model
lands; associated and derived fields are behavior around an instance and are not SoA
columns. Eligibility consumes the canonical layout/type facts rather than repeating a
second whitelist in `nupp.soa` and AOT.

## Capability regions and effects

One SoA owner is the root. Its child place is:

```text
root / field(stable field identity) / index(integer fact)
```

This is exactly the segment algebra from plan 050. Distinct fixed fields are disjoint;
two indexes of one field are disjoint only when existing integer facts prove them so.
A parent row overlaps all its fields at that index. A whole-column span is the field
child across the checked interval. Whole-owner movement, close, resize-by-replacement,
or hot-reload migration overlaps every column.

Several writable field spans may coexist when they select different fixed fields:

```nupp
local xs = rows:field("x")
local ys = rows:field("y")
```

Their regions are siblings. Two writable projections of `x`, or a whole-row write
while either child lives, are rejected. This is the ordinary non-AOT reason for
publishing field spans and the reason plan 041's omitted strided spans remain omitted:
SoA fields are unit-stride ordinary spans.

The intrinsic resolves the selected child path before applying its exclusive loan. It
does not first borrow the whole parent and then attempt to carve a child from an already
blocked value. This is the same partial-borrow rule that permits two fixed struct fields
to be borrowed independently under plan 050; method-call syntax is not authority to
widen the selected field back to the complete receiver.

Effect summaries record reads, writes, escapes, and return aliases against semantic
field paths. They do not serialize slab offsets or runtime column slots. A call that
accepts `soa.WriteSpan<T>` without a narrower contract may write any field; a wrapper
whose resolved body touches only `x` may preserve that precise local fact.

## Derives, reflection, and Tecs

The core feature publishes storage and semantic reflection. It does not know what a
component is. A Tecs-facing derive or library provider may consume:

- the ordered stored-field graph;
- the SoA storage descriptor and fingerprint;
- typed allocation, copy, swap, clear, and field-span operations;
- compile-time encode/decode helpers; and
- the component declaration's own stable identity.

A representative future component declaration is library syntax, not reserved Nupp
syntax:

```nupp
@derive(EcsComponent(storage = "soa"), Snapshot)
struct Transform2D
    x: float
    y: float
    rotation: float
end
```

The derive can replace Tecs's hand-maintained field lists, runtime constructor source,
runtime `fieldcodec` source generation, struct-size metadata, and positional snapshot
fingerprint. Tecs still owns archetype movement, dirty tracking, component identity,
snapshot policy, and migrations.

### Tecs snapshot framing

A SoA component remains one logical Tecs archetype column. Its fields are storage
segments inside that component, not independent components: splitting them into Tecs
columns would change archetype identity, queries, presence, dirty tracking, and
component migration.

The current Tecs binary fast path writes one dense FFI component with one
`putcdata(structSize * count)` and restores it with one `memcpy`. A SoA slab is not an
array of structs, so it must never enter that path under a fictional `structSize`.

Extend the per-component frame encoding explicitly:

```text
COLUMN_DENSE  = 0
COLUMN_SPARSE = 1
COLUMN_SOA    = 2

SoA component frame
    fieldCount
    for each saved field in fingerprint order
        byteCount
        raw contiguous field bytes
```

The component-table entry carries a versioned schema such as
`soa1|x:float,y:float,rotation:float`. The exact spelling is decided with Tecs's
existing fingerprint parser, but it must distinguish storage family and schema version
before parsing field data. The field headers need not repeat names or types: their
ordered definitions are in the saved schema. `byteCount` lets a reader validate and
skip a segment without trusting current code's layout.

Saving an unfiltered same-schema SoA component performs one `putcdata` per field.
Loading it performs one direct copy into each current field span. Padding between slab
segments is never serialized. Nested struct and fixed-array fields retain their own
ordinary value bytes inside their field segment, matching the current raw-FFI target
and endianness contract.

Custom component serialization, the table/JSON writer, and a filtered archetype may
use the correctness path:

```text
SoA row -> materialize ordinary component value -> existing serialize
decoded value -> whole-row scatter into SoA storage
```

That path allocates no runtime row proxy; it constructs a value only because the
serializer asked for one. A later filtered bulk gather is a measured optimization, not
a prerequisite for correctness.

Schema migration is representation-aware:

| Saved payload | Current storage | Load path |
| --- | --- | --- |
| SoA, identical schema | SoA | bulk-copy each field segment |
| SoA, changed schema | SoA | match saved fields by name/type; copy or convert surviving columns |
| AoS | SoA | decode saved row values, then scatter into current fields |
| SoA | AoS | read saved field segments, then construct/scatter current rows |
| table/JSON | either | existing keyed value deserialize plus the storage adapter |

New fields receive their declared/default initialization, removed fields are skipped,
and reordering follows saved names rather than current ordinals. An exactly compatible
field may copy as one block. A numeric conversion or changed aggregate shape uses the
generated per-value migration path and retains the current failure behavior for an
incompatible conversion.

Tecs currently writes `SNAPSHOT_VERSION = 1` and recognizes only dense and sparse
column encodings. Adding `COLUMN_SOA` changes framing and therefore bumps the snapshot
format version to 2. Preserve Tecs's existing policy that a reader refuses a snapshot
version it does not implement; do not make the version-2 reader guess at version-1
frames. AoS-to-SoA and SoA-to-AoS migration above apply to version-2 snapshots written
before and after a component changes storage. Importing a pre-feature version-1 save is
a separate application migration decision.

The Nupp SoA core supplies reflection, checked field spans, gather/scatter, and the
fingerprint inputs. Tecs continues to own the component table, column encoding values,
snapshot version, custom serializers, migration policy, and events.

## Diagnostics and inspection

Diagnostics must distinguish:

- the element type is not SoA-storable, naming the first rejected field;
- a field projection names no stored field or names associated/derived behavior;
- an index is outside the view;
- a row is requested where no materialization target exists;
- overlapping row, field, or column capabilities conflict;
- a virtual row is captured, stored, returned, or erased through `any`; and
- a live storage fingerprint does not match the code attempting to use it.

`nupp lsp inspect` on `rows[i].x` reports `Particle.x`, its value type, the SoA
column representation, and the active region. Definition, references, and rename go to
the struct field. Hover on `soa.Array<Particle>` reports the column list and storage
fingerprint without exposing addresses.

Add `nupp layout --soa Particle` or an equivalent extension to existing layout
inspection. It prints field order, type, alignment, width, and relative segment formula
for a target and count, plus the fingerprint. It must not allocate storage or run user
code.

Generated Lua inspection shows the column binding chosen for each direct field
expression. AOT remarks say whether the access became a contiguous scalar/vector load
or why lane lowering declined it.

## Implementation order

### S0 — Measurements and permanent semantics

- Add Tecs-shaped benchmarks for AoS, hand-written SoA, and three candidate ordinary
  Lua representations under JIT on/off.
- Cover transform integration, particle update, whole-row construction, snapshot
  field copy, archetype swap-remove, and a workload that consumes nearly every field.
- Record memory, trace aborts, interpreted and traced throughput, AOT scalar, and AOT
  lane results where available.
- Freeze row load, direct field write, compound-assignment evaluation order, whole-row
  scatter, and gradual-boundary examples before implementation.

### S1 — Canonical descriptor and owner

- Derive one target-aware SoA descriptor from the canonical struct layout graph.
- Publish compile-time field/type reflection and on-demand immutable runtime
  `soa.layoutof` metadata without exposing pointers or provenance.
- Implement overflow-checked aligned slab allocation and one affine owner.
- Add shared and exclusive private-representation views with count, slicing, sharing,
  commit, and automatic cleanup.
- Serialize only semantic descriptor facts in module interfaces and cache keys.

### S2 — Row and field places

- Teach checking, effects, regions, and generation the
  `field(stable identity)/index(fact)` SoA place.
- Lower direct field reads/writes and whole-row get/set with one bounds decision and
  exact source evaluation order.
- Add semantic field resolution, rename/references, hover, and generated-code
  inspection.
- Reject virtual-row escape rather than allocating a proxy fallback.

### S3 — Contiguous field spans

- Project shared and writable top-level fields as ordinary `nupp.span` views.
- Publish sibling field regions so multiple distinct writable columns coexist.
- Implement field-wise copy needed for owner replacement and Tecs archetype movement.
- Keep raw slab addresses, offsets, and pointer tables private.

### S4 — AOT lane lowering

- Publish SoA place facts to checked AOT IR rather than matching type text or method
  spellings.
- Lower field columns as unit-stride memory, preserve exact scalar tails, and use the
  existing gang-width decision.
- Differentially test ordinary Nupp, forced-scalar C, and lane C for row and field
  operations, alias rejection, bounds failures, NaNs, and signed zero.
- Add a check/remark explaining when a SoA loop remains scalar.

### S5 — Derive and Tecs acceptance

- Add the minimum derive-recipe capability needed to construct a typed storage adapter
  from the public SoA descriptor.
- Port representative Tecs `Transform2D` and particle stores without runtime source
  generation or hand-maintained field arrays.
- Add one `COLUMN_SOA` component-frame encoding, bump the Tecs snapshot format, and
  write one validated field subframe per stored field without changing archetype
  component identity.
- Generate positional snapshot codecs and verify same-schema bulk restore, changed
  schemas, custom/table fallbacks, and AoS/SoA migration explicitly.
- Measure system source size, component-registration machinery removed, snapshot
  throughput, extraction throughput, memory, and frame time.

No phase leaves a runtime proxy or provisional representation to be removed by the
next phase.

## Performance gates

- An ordinary direct SoA field loop under LuaJIT must compile and have no per-row
  allocation, closure creation, reflective lookup, or helper call in its recorded body.
- Warm traced direct-field throughput must be within 10% of equivalent hand-written
  parallel cdata arrays before AOT.
- AOT lane code must use unit-stride loads/stores and match the hand-written SoA C
  baseline within 10% on the accepted transform and particle kernels.
- Same-schema binary snapshot save and restore perform one bulk operation per stored
  field, with no per-entity materialization; record their throughput beside the current
  one-operation-per-AoS-component baseline.
- Whole-row materialization must be measured and documented; it is not required to
  beat AoS, but direct field code may not materialize a row accidentally.
- Owner allocation performs one native allocation independent of field count.
- Ordinary projects that do not import `nupp.soa` emit no descriptor, helper, field
  table, or generated byte.
- Warm checking and private-body invalidation may regress by at most 5%; full checking,
  summary size, and peak checker memory by at most 10% on the plan 050 baseline.

## Verification matrix

Tests must prove:

- the same struct can be used simultaneously in ordinary AoS and SoA storage;
- `layoutof(T)`, FFI, equality, and value construction are unchanged;
- every eligible top-level field receives one aligned contiguous column;
- nested structs and fixed arrays remain unsplit field values;
- unsupported and capability-bearing fields are rejected at allocation checking;
- direct reads, writes, compound assignments, and side-effecting indexes preserve
  ordinary evaluation order;
- whole-row reads materialize independent values and whole-row writes scatter once;
- no virtual row escapes, boxes, or crosses a gradual boundary;
- shared/writable slices, field spans, split ranges, and cleanup obey ownership;
- distinct writable fields coexist and overlapping row/field/index regions do not;
- field rename/references use declaration identity rather than the string spelling;
- compile-time and requested runtime reflection agree on field order, names, types,
  widths, alignments, segment arithmetic, and fingerprint without exposing addresses;
- JIT-on, JIT-off, scalar AOT, and lane AOT answers agree;
- hot reload rejects or migrates incompatible live storage rather than reinterpreting
  it;
- snapshots retain one Tecs component column, identify their storage schema, frame SoA
  fields as subsegments, never raw-copy SoA as AoS, and cover the full migration
  matrix; and
- Tecs acceptance removes runtime field codec generation for the selected components.

## Completion criteria

This plan is complete when:

- one explicit container type distinguishes SoA storage from ordinary struct arrays;
- normal indexed field source lowers without runtime row objects;
- whole-row value semantics and gradual boundaries are unambiguous;
- one owned slab supplies safe shared, writable, sliced, and field-column views;
- compile-time derives and on-demand runtime consumers can inspect the same immutable
  SoA layout facts without acquiring storage access;
- general capability regions describe every row and field alias decision;
- AOT consumes published unit-stride facts and emits inspected SIMD code;
- a Tecs component derive replaces the corresponding field lists, runtime codegen,
  layout metadata, and snapshot codec, with field subframes inside one component
  column;
- ordinary non-SoA programs pay no build or runtime cost; and
- the full suite, fixpoint, bootstrap, cross-target layout, ABI, JIT, AOT differential,
  and Tecs performance gates pass.
