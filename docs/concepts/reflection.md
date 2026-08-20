# Reflection

Reflection asks what a declared type means without making an instance carry the
answer. `Record.reflect()` answers at runtime, and `nupp.reflect(T)` answers
while the program is compiled.

```nupp:playground
local record User
    id: integer
    name: string = "anonymous"
end

local info = User.reflect()
print(info.name, info.fields[1].name)
```

The two forms are separate:

| Where it runs | Entry point | Result |
| --- | --- | --- |
| Comptime | `nupp.reflect(T)` | an immutable semantic graph used to generate or validate code |
| Runtime | `Record.reflect()` | one cached immutable descriptor for that record |

Both describe declarations, not object layout. For the target-specific layout of
a `struct`, use `nupp.sizeof`, `nupp.alignof`, `nupp.offsetof`, and
`soa.layoutof`. See [Layout
reflection](structure-of-arrays.md#layout-reflection) for what those report.

## Runtime reflection

Call `Record.reflect()` when runtime code needs the declaration. It returns the
same descriptor on every call. The descriptor is read-only and exposes the
record's `kind`, `name`, `fields`, `annotations`, and `fingerprint`, plus
`type`, the original `Type<Record>`.

```nupp
local record User
    id: integer
    name: string = "anonymous"
end

local info = User.reflect()
assert(info.type == User)
assert(info == User.reflect())
assert(info.fields[1].name == "id")
```

The compiler emits the small runtime registry only for a record that calls
`reflect()` or needs it for a derive, and the descriptor itself is allocated on
the first call. A program that neither reflects on a record nor derives JSON
pulls in neither the data nor the registry.

### Extensions

`info:extension(extension)` is the cache boundary for work derived from a
descriptor. An extension is a table with a `build` function; the first call
builds it against that descriptor, and every later call with the same extension
returns what was built. Memoization is under the extension itself rather than
under a name, so two extensions that happen to describe the same thing stay
separate.

The state of a build in progress is kept as well as the finished one. An
extension whose `build` reflects its way back to the descriptor it is being
built for is reported as a recursive initialization instead of recurring until
the stack runs out, and a build that failed once is reported the same way every
time rather than retried.

The JSON derive is the mechanism's first user: its decoder and field codec are
not built when the record is declared, and the JSON extension builds them the
first time JSON is used. Extension registration is a runtime implementation API
for Nupp's own libraries rather than a public user-defined extension API, so
programs use the JSON and derive members below rather than `_G.nupp`.

::: deepdive
Format-specific behavior is allocated against the descriptor on first request
rather than generated for every declaration that could want it. Generating per
declaration pays for every format on every record that mentions it, whether or
not a value is ever encoded, and the cost lands in the binary rather than in the
program that asked for the format.

See [NEP 3](../neps/0003-comptime.md) for more information.
:::

## Type witnesses

Every record has a visible nominal type value: its declaration name is a
`Type<Record>`, distinct from an instance of that record. It is still the
record's ordinary runtime table, so constructors, static members, and method
dispatch keep their Lua behavior. See [Names hold their
table](../type-system/records.md#names-hold-their-table) for how the two stand
apart in the type system.

```nupp
local record User
    id: integer
    name: string
end

local witness: Type<User> = User
local user: User = new User(id = 7, name = "ada")

assert(witness == User)
assert(User ~= user)
```

An API that accepts a declared record takes `Type<T>`. A record name is never a
`metatable<T>`, which remains for an explicit table passed to Lua's metatable
functions.

::: deepdive
A caller supplies the declaration and nothing else. Passing a separate type
witness beside every value would thread it through every generic that forwards
the call, so a signature with nothing to do with reflection would acquire a
parameter because something three layers down wanted one. Taking the
declaration itself keeps the witness where the API needs it and out of every
signature between here and there.
:::

## JSON through a type witness

`@derive(nupp.derive.JSON)` makes JSON available both as generated record
members and through `nupp.data.json`. The namespace form accepts the record name
directly, so callers never construct or pass a separate schema object.

```nupp
@derive(nupp.derive.JSON)
local record User
    id: integer
    name: string
end

local user = new User(id = 7, name = "ada")
local out = string.buffer.new()
user:writeJSON(out)
local text = out:get()
nupp.data.json.writeAs(User, user, out)
local sameText = out:get()
local restored, problem = nupp.data.json.decodeAs(User, text)

assert(text == sameText)
assert(problem == nil)
assert(restored and restored.id == 7)
```

`writeJSON` and the static `fromJSON` discover the declaration from the value's
own metatable. `writeAs` and `decodeAs` take the `Type<T>` witness explicitly,
which is what an API boundary wants, or code that runs before a value exists.
See [Declaration derives](../reference/derives.md#json) for the options, wire
format, and validation rules, and [JSON](../modules/nupp/data/json.md) for the
generic encoder underneath them.

## Comptime reflection

`nupp.reflect(T)` resolves a type in type position and hands comptime an
immutable, target-independent descriptor. It is for generators and validators,
and it adds no runtime descriptor to the program.

```nupp
local record Position
    x: number
    y: number
end

const PositionCodec: nupp.reflect.FieldCodec<Position> = comptime do
    return nupp.reflect.fieldCodec(nupp.reflect(Position))
end

local function encode(position: Position): {[string]: any}
    return PositionCodec:encode(position)
end
```

### Descriptor graph

The descriptor is an acyclic indexed graph, which is what keeps a recursive type
finite: `root` selects a node in `types`, and every edge is an index into that
same array. It covers nominal records, interfaces, and structs; shapes, fields,
and indexers; function signatures and packs; generic arguments; unions and
intersections; ownership wrappers; and arrays, pointers, and C types. The root's
`kind`, `name`, `fields`, `annotations`, and `fingerprint` are available
directly as well.

Comptime code may read descriptor members, use `#`, and traverse arrays with
deterministic `ipairs` or `pairs`. Views keep their identity for equality,
reject mutation, and cannot escape as runtime tables.

### Annotations and fingerprints

Checked typed annotations travel with the descriptor as an ordered
`annotations` array, and an `@ref` argument is an edge into the same graph.
Annotation names, arguments, values, and referenced types all contribute to the
fingerprint, which is computed from the canonical semantic graph rather than
from the checker's process-local type identities.

A generated result is therefore invalidated when serialization metadata changes
and not only when a field type does: renaming a JSON key with `@json(name =
"user_id")` gives the descriptor a new fingerprint, so whatever a comptime block
generated from it is generated again.

### Field codecs

`nupp.reflect.fieldCodec` is a materialization boundary. It produces a
`nupp.reflect.FieldCodec<R>` for the same nominal record `R` and copies exactly
that record's declared present fields with `rawget`. Its compatibility
fingerprint is `t:` followed by those field names in declaration order, and the
declared codec type must name the same record. Reflection of a runtime value, an
unresolved type, or a non-record codec input is refused. See [Opaque
results materialize at a
declaration](comptime.md#opaque-results-materialize-at-a-declaration) for the
rule that governs where the result may land.

## FAQ

### Does reflection add metadata to every record?

No. A record gets a runtime blueprint only when the program calls `reflect()` on
it or derives something that needs one, and the descriptor is built on the first
call rather than at declaration. See [Runtime reflection](#runtime-reflection)
for what the registry costs.

### Should a generator reflect at comptime or at runtime?

Reflect at comptime when the result is code or a validation that can be decided
while compiling, and at runtime when the program has a value in hand and needs
its declaration. Comptime descriptors are target-independent and leave nothing
behind; runtime descriptors are cached per record and carry the extension cache.

### Can reflection report a struct's memory layout?

No. Reflection reads declared meaning, so a field's offset is not one of its
answers. Use `nupp.sizeof`, `nupp.alignof`, `nupp.offsetof`, and `soa.layoutof`,
which report against the build's `layoutTarget`.

::: seealso
- [comptime.md](comptime.md) for the blocks and type functions that consume
  comptime descriptors
- [derives.md](../reference/derives.md) for the derives built on runtime
  descriptors
- [records.md](../type-system/records.md#names-hold-their-table) for the type
  witness in the type system
- [NEP 3](../neps/0003-comptime.md) for the record of the design
:::
