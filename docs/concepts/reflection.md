# Reflection

Reflection lets code ask what a declared type means without making an instance
carry metadata. It has two deliberately separate forms:

| Where it runs | Entry point | Result |
| --- | --- | --- |
| Comptime | `nupp.reflect(T)` | an immutable semantic graph used to generate or validate code |
| Runtime | `Record.reflect()` | one cached immutable descriptor for that record |

Both describe declarations, not object layout. Use `nupp.sizeof`, `nupp.alignof`,
`nupp.offsetof`, and `layoutof` for the target-specific layout of a `struct`.

## Type witnesses

Every record has a visible nominal type value. Its declaration name is a
`Type<Record>`, distinct from an instance (`Record`). It is still the record's
ordinary runtime table, so constructors, static members, and method dispatch
keep their Lua behaviour.

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

`metatable<T>` remains for explicit Lua metatable construction, but a record
name is never one. An API that accepts a declared record takes `Type<T>`.

## Runtime reflection

Call `Record.reflect()` when runtime code needs the declaration. It returns the
same descriptor on every call. The descriptor is read-only and exposes the
record's semantic blueprint, including its `kind`, `name`, `fields`,
`annotations`, and fingerprint, plus `type`, the original `Type<Record>`.

```nupp
local record User
    id: integer
    name: string = "anonymous"
end

local info = User.reflect()
print(info.name)           -- User
print(info.fields[1].name) -- id
assert(info.type == User)
assert(info == User.reflect())
```

The compiler emits the small runtime reflection registry only for a record that
uses `reflect()` or needs it for a derive. The descriptor itself is allocated on
the first call. A program that neither reflects on a record nor derives JSON
does not pull in reflection data or its registry.

### Extensions

`info:extension(key)` is the cache boundary for work derived from a descriptor.
An extension is allocated at runtime the first time that particular descriptor
asks for it, then cached by descriptor and extension key. Recursive
initialization and failed initialization are reported instead of exposing a
partial value.

The JSON derive uses this mechanism: its decoder and field codec are not built
when the record is declared; the JSON extension builds them the first time JSON
is used. Extension registration is currently a runtime implementation API used
by Nupp libraries, rather than a public user-defined extension API. Programs
should use the public JSON and derive members below rather than `_G.nupp`.

## JSON through a type witness

`@derive(nupp.derive.JSON)` makes JSON available both as generated record
members and through `nupp.data.json`. The namespace form accepts the record
name directly; callers never construct or pass a separate schema object.

```nupp
@derive(nupp.derive.JSON)
local record User
    id: integer
    name: string
end

local user = new User(id = 7, name = "ada")
local text = nupp.data.json.encode(user)
local sameText = nupp.data.json.encodeAs(User, user)
local restored, problem = nupp.data.json.decode(User, text)

assert(text == sameText)
assert(problem == nil)
assert(restored and restored.id == 7)
```

`encode` discovers the record declaration from the value. `encodeAs` and
`decode` take its `Type<T>` witness explicitly, which is useful at an API
boundary or before a value exists. The JSON options, wire format, and validation
rules are documented in [Declaration derives](../derives.md#json); the generic
cjson-compatible API is documented in [JSON](../json.md).

## Comptime reflection

`nupp.reflect(T)` resolves a type in type position and gives comptime an
immutable, target-independent descriptor. It is for generators and validators;
it does not add a runtime descriptor to the program.

```nupp:playground
local m = {}

local record Position
    x: number
    y: number
end

const PositionCodec: nupp.reflect.FieldCodec<Position> = comptime do
    return nupp.reflect.fieldCodec(nupp.reflect(Position))
end

function m.encode(position: Position): {[string]: any}
    return PositionCodec:encode(position)
end

return m
```

The descriptor is an acyclic indexed graph so recursive types remain finite:
`root` selects a node in `types`, and edges are indices into the same array. It
covers nominal records, interfaces, and structs; shapes, fields, indexers,
functions and packs; generic arguments; unions and intersections; ownership
wrappers; arrays, pointers, and C types. The root's common `kind`, `name`,
`fields`, `annotations`, and `fingerprint` are available directly as well.

Checked typed annotations travel with the descriptor. An `@ref` argument is an
edge into the same graph, and annotation names, arguments, values, and
references contribute to the fingerprint. A generated result is therefore
invalidated when serialization metadata changes, not merely when a field type
changes.

Comptime code may read descriptors, use `#`, and traverse arrays with
deterministic `ipairs` or `pairs`. Views preserve equality identity, reject
mutation, and cannot escape as runtime tables. `nupp.reflect.fieldCodec` is a
materialization boundary: it produces a `nupp.reflect.FieldCodec<R>` for the
same nominal record and copies its declared present fields with `rawget`.

## Diagnostics

- **NUPP2414**: an opaque reflection result reached a binding that cannot
  materialize it.
- **NUPP2415**: a declared materialization boundary or provider result failed
  validation.
- **NUPP2416** / **NUPP2418**: reflection or its provider rejected the request.

## Next

- [Comptime](comptime.md): evaluation, type functions, and materialization.
- [Declaration derives](../derives.md): checked generated members and JSON
  schema options.
- [Records](../type-system/records.md): nominal record declarations and their
  construction rules.
