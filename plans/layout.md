# Struct layout reflection

## Decision

Nupp will answer, at run time, what a `struct`'s layout is: its field names in
declaration order, each field's C type, offset, size and trailing padding, the
whole struct's size, and a fingerprint derived from all of it.

It will not define a serialization format, a wire protocol, or an interface a
declaration has to implement. It answers *what is this thing's layout* and
libraries decide what to do with the answer.

## Why this shape

Reification is what breaks serialization. A `struct` instance is cdata, and
`string.buffer.encode` raises `cannot serialize 'cdata'` with no hook to
install, `pairs` needs a `__pairs` on the metatype, and `type` answers
`"cdata"`. So the largest speedup the language has is also the change that
breaks the snapshot path — and `reifiable-record` (NUPP2509) has to warn about
that rather than recommend it freely. Fixing what reification broke is a
different obligation from adding a serialization framework.

The line is drawn where tecs draws it, because tecs has already built this and
is the workload. `src/tecs/internal/fieldcodec.tl` is 166 lines that *generate
Lua source at run time* (`load(source, chunkName, "t")`) from a component's
declared fields, producing a keyed serializer, a positional `serializeRaw` that
writes into a `string.buffer`, and a matching `deserializeRaw`. Beside it,
`internal/snapshot.tl` is 2411 lines of archetypes, layer filtering,
`filterQuery`, custom data entries, `OnSnapshotSave` listeners and migration
policy.

The first is what a compiler that knows the layout should make unnecessary. The
second is application concern nupp cannot see and should not try to.

Three things in tecs decide the design:

- **The fast path is not a per-value method.** It is
  `writeColumnRaw(c, ffiOffsetCharPtr(column, structSize), structSize * count)`
  — one `putcdata` for an entire column. What that needs from the language is a
  size and a guarantee of contiguity. A `Serializable` interface with a
  `save(buf)` method would optimize the case that does not matter.
- **The opt-out is load-bearing.** tecs's `Text` component holds non-portable
  glyph slab pointers, supplies a custom `serialize`, and deliberately skips the
  auto-installed raw codec; `transient` components are never written at all. A
  protocol a declaration cannot decline would be wrong for exactly the data that
  most needs to decline.
- **Reification makes the codec simpler, not harder.** `fieldcodec` uses
  `rawget` because a table instance can legitimately lack a declared field,
  and notes that "a cdata instance has no raw table part... its struct carries
  every declared field".

## What is already true

Measured rather than assumed:

- `ffi.sizeof` and `ffi.offsetof` are public and sufficient. `offsetof` works on
  the anonymous struct ctypes nupp emits, and on nested, pointer and fixed-array
  fields.
- A C spelling sizes on its own for every primitive, `float[4]` (16) and
  `void *` (8).
- **A nested struct's size does not.** Nupp emits anonymous structs, so
  `ffi.sizeof("Inner")` fails and the size has to come from the ctype binding.
  The lowering therefore passes nested ctypes as arguments, the way
  `ffi.typeof("struct { $ inner; }", Inner)` already does.
- `ffi.typeinfo` can walk names and offsets, and `src/nupp/compiler/cdecl.nupp` already
  depends on it — but at compile time. Extending that dependency into generated
  user code is a bigger promise than emitting the names, which the compiler
  already has.
- Field size and stride are different questions with different consumers. A
  prototype that derived size from the next field's offset reported an `int8_t`
  before a `double` as eight bytes. Both are reported, separately.

## The surface

A compiler-provided global, beside `carray`, `cheader` and `buffer`:

```nupp
struct m.Vec3
    x: float
    y: float
    z: float
end

const layout = layoutof(m.Vec3)
print(layout.size)                       -- 12
print(layout.fingerprint)                -- x:float,y:float,z:float|12
for _, f in ipairs(layout.fields) do
    print(f.name, f.ctype, f.offset, f.size, f.padding)
end
```

Typed by a prelude declaration, so a misspelled member is an error rather than
nil:

```nupp
record Layout
    name: string
    size: integer
    fingerprint: string
    fields: {LayoutField}
end

record LayoutField
    name: string
    ctype: string
    offset: integer
    size: integer
    padding: integer
end
```

`layoutof` on anything that is not a struct is an error. A record has no layout,
and answering with an empty one would read like a struct with no fields.

## The lowering

At the **call site**, not the declaration, so a program that never asks pays
nothing:

```lua
-- the struct, unchanged from today
const __nuppFfi = require("ffi"); const __nuppMt_Vec3 = {__index = {}} m.Vec3 = __nuppFfi.metatype(__nuppFfi.typeof("struct { float x; float y; float z; }"), __nuppMt_Vec3)

-- layoutof(m.Vec3)
const layout = __nuppLayout(m.Vec3, "Vec3", "x:float,y:float,z:float")

-- layoutof(m.Outer), whose `inner` field is another struct
const outer = __nuppLayout(m.Outer, "Outer", "inner:$,w:float", m.Inner)
```

The compiler emits only what it knows statically: the name, and a spec of field
names against C spellings, with `$` consuming the next ctype argument for a
field whose type is anonymous. Size, offsets and padding are this platform's, so
the helper asks for them at load and caches per ctype — the same hoisted-helper
shape as `__nuppArray` and `__nuppBuffer` in `src/nupp/compiler/gen.nupp`.

## Status

L1 through L4 are done; `tests/layouttest.lua` covers them by running the
generated code and checking every number against `ffi.sizeof`/`ffi.offsetof`
rather than against a constant written down here.

Three things the implementation changed from this plan, and one bug it found:

- **A fixed C array is not a struct field at all.** `reifiableField` admits
  primitives, a nested struct, and pointers -- not `carray` -- so `v: float[4]`
  is NUPP2201 and L2's array case does not exist. That is a real gap in the
  language for FFI work, since C structs commonly have array members, but it is
  a different piece of work.
- **`$` does not reach the reported layout.** The first cut used it as the
  ctype for a nested field, which leaked an encoding into user-facing data and
  collapsed every pointer to `void *` -- so `Inner*` and `Other*` shared a
  fingerprint. Fields now report their declared spelling (`Inner`, `Inner *`)
  and the marker only drives sizing.
- **The fingerprint expands a nested struct rather than naming it.** L3's open
  question, decided: naming it misses a change that keeps the size, so swapping
  `Inner`'s floats for int32s leaves `inner:Inner,w:float|12` matching itself
  across the change and a reader takes ints for floats. Expansion is
  `inner:{a:float,b:float},w:float|12`. It terminates because a by-value cycle
  is now refused, and a pointer is not followed since the pointee is not part of
  this layout.

Found while asking whether the expansion could cycle: **a struct could contain
itself by value**, checking clean and dying at load with `typeof: type parameter
expected, got nil`, because the ctype names itself before it exists. Mutual
by-value containment did the same. Both are NUPP2201 now, with the repair named.

Separately, and not fixed here: **a struct cannot point at itself either**, for
the same reason at one remove — an anonymous ctype cannot refer to itself, so
every linked list is unreachable. Recorded in plans/todo.md, and pinned by tests
that should invert when it is fixed.

## Milestones

1. ~~**L1, the helper and the lowering.**~~ Done. `__nuppLayout` with a weak-keyed cache,
   `layoutof` recognized in `src/nupp/compiler/check/ffi.nupp` the way `carray` is,
   emitted in `src/nupp/compiler/gen.nupp`. Primitive fields only. Tests run the
   generated code and assert offsets against `ffi.offsetof` independently.
2. ~~**L2, the field shapes a struct can actually hold.**~~ Done, minus fixed
   arrays, which a struct cannot hold. Nested structs, pointers, optional
   pointers. This is where the `$` argument path is
   exercised, and where a wrong answer is silent rather than loud, so each shape
   wants a test that checks the offset against the FFI rather than against a
   number someone wrote down.
3. ~~**L3, the fingerprint.**~~ Done. Canonical ordering, size included, and
   nested structs expanded. The decision on whether it Including it makes a 32-bit save refuse on 64-bit, which is
   correct, and is why tecs pairs its fingerprint with name-keyed migration.
   Nupp produces the fingerprint and stays out of the migration policy.
4. ~~**L4, the acceptance use.**~~ Done, and it answered a different question
   than it asked. `tests/bulkcolumntest.lua` writes a whole column as one
   `putcdata` of `layoutof(T).size * count`, reads it back into fresh memory,
   and refuses a column whose saved fingerprint is not this layout's. That is
   the hot side of `internal/snapshot.tl`, and it needs nothing from the
   language but the stride and the fingerprint.

   The criterion was wrong, though. It asked whether `fieldcodec.tl` becomes
   unnecessary, and it does not — because `fieldcodec` is for **table**
   components, which have no C layout at all. Its own header says so: "Snapshot
   codecs generated from a table component's declared `fields`". Reflection
   cannot help a value that is not laid out, so the two serve different halves.

   What reflection replaces is the hand-maintained constant: `structSize`, and
   things like `gpu/meshlayout.tl`'s `INSTANCE_FLOATS = 16` that must agree with
   a struct and a shader and can silently stop agreeing. That is a smaller claim
   than the milestone made and a true one.

## Open questions

- Whether `layoutof` should also answer for a `cdef struct`, which has a real C
  name rather than an anonymous one and therefore does size by spelling.
- Whether the fingerprint should describe nested structs recursively or by their
  own fingerprint. Recursion is more precise and makes the string unbounded.
- Whether a generic struct can exist at all; `suggestStruct` excludes generics
  from the reifiable-record suggestion, which suggests not, but that is a
  different question from whether the declaration is legal.
- Whether anything should be emitted for a struct nothing asks about. Emitting
  at the call site says no, which is right for cost and wrong for a library that
  wants to enumerate every struct in a module.

## Non-goals

- A wire format. tecs's is 2411 lines for reasons nupp cannot see.
- A `Serializable` interface every reified declaration implements. The opt-out
  is the part that matters most, and an interface makes opting out the
  exception rather than the ordinary case.
- Migration policy. Nupp says the layout changed; what to do about it is the
  application's.
- Anything for plain records. They are tables with no layout, so "how do I
  serialize a record" stays "walk it yourself".
