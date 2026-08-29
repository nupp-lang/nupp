---
order: 680
title: Declaration derives
---

`nupp.derive` holds the three bundled derive providers and the recipe API a
package uses to publish its own. `@derive` names a provider on a record or
struct declaration. The provider decides which targets it admits and adds the
closed set of checked members or data that it returns.

The bundled recipes render by appending into a `string.buffer`, so a `lua51`
target needs a `text.buffer` provider selected. Without one, a `@derive` naming a
provider reports `NUPP3012` on the annotation that named it. The browser backend
selects one, so a page needs nothing further.

```nupp:playground
@derive(nupp.derive.Debug, nupp.derive.JSON)
local record User
    @json(name = "user_id")
    id: integer

    name: string = "anonymous"

    tags: {string} = {}
end

local user = new User()
local out = string.buffer.new()
local writer = nupp.data.json.writer(out)
user:writeJSON(writer)
writer:close()
print(user:debug(), out:tostring())
```

Applying a provider is a declaration-augmentation phase, not a text macro: it
cannot add imports, top-level declarations, modules, records, interfaces, or
independently nameable types. The bundled providers are:

- [`nupp.derive.Debug`](#debug): `debug(self): string` and `nupp.Debug`
  conformance.
- [`nupp.derive.JSON`](#json): `writeJSON(writer)`, a static `fromJSON`,
  `fieldCodec`, and
  `nupp.data.json.JSONEncodable` conformance.
- [`nupp.derive.Serde`](#serde): one format-neutral schema and physical binding
  for a record or struct, with no generated format methods.

Generated members participate in normal member lookup, generic inference, and
interface checking. A written member of the same name is a compile-time
conflict. Stacked `@derive` applications combine, but a provider cannot be
requested twice. See [annotations.md](annotations.md#derive) for where `@derive`
sits among the built-in annotations.

## Debug

`debug(self): string` renders a record or fixed-layout struct the way the
declaration reads, so what comes back names the declaration and its fields in
declaration order. The derive records a format-neutral schema and physical
binding; the generic formatter prepares and caches its traversal on first use.

```nupp
@derive(nupp.derive.Debug)
local record Point
    x: integer
    y: integer
end

local p = new Point(x = 3, y = -1)
print(p:debug())
```

```text
Point { x = 3, y = -1 }
```

Strings are quoted, map keys are sorted by byte order so two runs agree, nested
records render through their own `debug`, and a runtime table that reaches
itself renders as `<cycle>`.

```nupp
@derive(nupp.derive.Debug)
local record Tag
    name: string
end

@derive(nupp.derive.Debug)
local record Post
    title: string
    views: integer
    tags: {Tag}
    scores: {[string]: integer}
end

local post = new Post(
    title = "hello",
    views = 12,
    tags = {new Tag(name = "a"), new Tag(name = "b")},
    scores = {zeta = 1, alpha = 2}
)
print(post:debug())
```

```text
Post { title = "hello", views = 12, tags = {Tag { name = "a" }, Tag { name = "b" }}, scores = {["alpha"] = 2, ["zeta"] = 1} }
```

### Field visibility

A `@debug` field annotation decides what a field contributes. `redact` keeps the
name and replaces the value, which is what a secret wants; `skip` removes the
field from the output entirely.

```nupp
@derive(nupp.derive.Debug)
local record Credentials
    user: string
    @debug(redact = true)
    password: string
    @debug(skip = true)
    cache: any
end

local c = new Credentials(user = "ada", password = "hunter2", cache = {1, 2})
print(c:debug())
```

```text
Credentials { user = "ada", password = <redacted> }
```

`Debug` and `Serde` on the same declaration share one schema recipe. `Debug`
alone keeps that binding internal and does not make the declaration
`nupp.data.serde.Serializable`. Code that already retains a public binding can
prepare the same formatter explicitly and append without constructing the final
string:

```nupp
@derive(nupp.derive.Debug, nupp.derive.Serde)
local struct Vec2
    x: float
    y: float
end

local prepared = nupp.data.serde.prepareDebug(nupp.data.serde.of(Vec2))
local output = string.buffer.new()
prepared:write(new Vec2(1.25, 2.5), output)
assert(output:tostring() == "Vec2 { x = 1.25, y = 2.5 }")
```

## Serde

`Serde` derives one logical `nupp.data.serde.Schema` and one
`nupp.data.serde.Binding<T>`. It applies to records and fixed-layout structs,
and generates no `writeJSON`, `fromJSON`, XML, or CBOR methods. A codec prepares
the binding separately and caches its format-specific data.

```nupp
@derive(nupp.derive.Serde)
local record User
    id: uint32
    name: string?
end

local binding = nupp.data.serde.of(User)
local prepared = nupp.data.serde.json():prepare(binding)
local text = prepared:encode(new User(id = 7, name = "ada"))
local restored, problem = prepared:decode(text)

assert(problem == nil)
assert(restored and restored.id == 7)
```

The same type witness works for a struct:

```nupp
@derive(nupp.derive.Serde)
local struct Vec3
    x: float
    y: float
    z: float
end

local binding: nupp.data.serde.Binding<Vec3> = nupp.data.serde.of(Vec3)
```

Derived fields currently admit booleans, strings, finite numbers, integers
through 32 bits, optionals, arrays, string-keyed maps, and other declarations
that also derive `Serde`. Pointer-bearing struct fields are rejected because a
pointer does not describe its extent or ownership. See [Schema-driven
serde](../concepts/serde.md) for dynamic schemas, profiles, extensions, and the
prepared JSON path.

## JSON

`JSON` generates `writeJSON(writer)`, a static `fromJSON`, a `fieldCodec`, and
`nupp.data.json.JSONEncodable` conformance. Encoding writes through the checked
buffer-backed writer; it does not allocate a complete result string. Record and
shape fields follow declaration order and string map keys sort by byte order, so
the same value always produces the same bytes. Encoded field names and literal
values are cached lazily on the derived schema.
If encoding fails, bytes appended before the failure remain in the buffer;
reset or discard it when the surrounding operation needs atomic output.

```nupp
@derive(nupp.derive.JSON, nupp.derive.Debug)
local record User
    @json(name = "user_id")
    id: integer
    name: string
end

local user = new User(id = 7, name = "ada")
local out = string.buffer.new()
local writer = nupp.data.json.writer(out)
user:writeJSON(writer)
writer:close()
print(out:tostring())

local decoded = User.fromJSON('{"user_id": 7, "name": "ada"}')
print(decoded and decoded:debug())
```

```text
{"user_id":7,"name":"ada"}
User { id = 7, name = "ada" }
```

### Decoding errors

`fromJSON` returns `T?, string?`, and the error names the path that failed
rather than saying the document was bad:

```nupp
@derive(nupp.derive.JSON)
local record User
    @json(name = "user_id")
    id: integer
    name: string
end

print(select(2, User.fromJSON('{"user_id": 7, "name": "ada", "nmae": 1}')))
print(select(2, User.fromJSON('{"user_id": "seven", "name": "ada"}')))
print(select(2, User.fromJSON('{"user_id": 1e300, "name": "ada"}')))
print(select(2, User.fromJSON('{"name": "ada"}')))
```

```text
$: unknown field "nmae"
$.user_id: expected finite number
$.user_id: expected integer in range
$.user_id: required field is absent
```

### Options

A record decides what happens to keys it does not know.

| Option | Effect |
| --- | --- |
| `@json(unknown = "reject")` | rejects unknown keys, and is the default |
| `@json(unknown = "ignore")` | ignores unknown keys |

A field decides how it appears on the wire.

| Option | Effect |
| --- | --- |
| `name = "wire_name"` | renames the key |
| `omit = true` | removes the field both ways, and requires a default |
| `omitEmpty = true` | omits nil, false, empty strings and empty tables, encoding only |

`omitEmpty` is encoding only, which is the part worth knowing: a field left out
of the output is still required coming back in.

```nupp
@derive(nupp.derive.JSON)
local record User
    id: integer
    @json(omitEmpty = true)
    tags: {string}
end

local user = new User(id = 7, tags = {})
local out = string.buffer.new()
local writer = nupp.data.json.writer(out)
user:writeJSON(writer)
writer:close()
local text = out:tostring()
print(text)
print(select(2, User.fromJSON(text)))
```

```text
{"id":7}
$.tags: required field is absent
```

Use `omit` with an explicit field default when a field should disappear from
both directions:

```nupp
@json(omit = true)
secret: string = "redacted"
```

### Schemas

Booleans, strings, finite numbers, exactly representable integer widths,
optionals, arrays, tuples, string-keyed maps, finite shapes, and records
deriving JSON are all supported. `int64` and `uint64` are rejected, because a
JSON number cannot round-trip their full range, and the erased `integer` type is
checked against the safe interval at run time.

Strings must be valid UTF-8, and a cycle or excessive nesting fails with the
JSON path that reached it. Decoding uses Nupp's strict SIMD-accelerated codec and
preserves null with `nupp.data.json.NULL` while it validates the raw value.

The JSON field codec is allocated lazily as a runtime reflection extension. Use
`nupp.data.json.writeRecord`, `writeAs(User, value, writer)`, and
`decodeAs(User, text)` when a type-witness API fits better than generated
members. The allocating `encodeRecord` and `encodeAs` wrappers remain available
when a complete string is specifically required. See
[reflection.md](../concepts/reflection.md#runtime-reflection) for the witness
and allocation model, and [](nupp.data.json) for the rest of the codec.

## Package providers

A package may export a derive provider as a `comptime function`. Its exact
signature names the one existing interface it implements:

```nupp
comptime function M.derive(info: nupp.derive.Info): nupp.derive.Result<M.Inspect>
    -- inspect info and return a closed recipe
end
```

A consumer applies the resolved exported symbol, not a runtime function value:

```nupp
local inspect = require("inspect")

@derive(inspect.derive)
local record Credentials
    username: string
    password: string
end
```

Applying the provider also claims `M.Inspect`. An equal written
`is inspect.Inspect` is redundant and coalesced. Interface defaults are
inherited normally and associated requirements are checked normally. A provider
can fill a bodyless callable requirement or declare a new function member with a
closed comptime-built signature. Generic, variadic, overloaded, and effectful
provider declarations are not part of the first recipe version.

::: deepdive
`Debug` and `JSON` are ordinary exported `comptime function` declarations
implemented in `src/nupp/derive.nupp`, and the compiler has no provider-name or
operation switch for them. Both travel through the same sealed comptime worker,
immutable `Info`, versioned result envelope, cache and recipe lowering a package
provider uses, and their schema configuration (`@debug` and `@json`) is part of
the semantic annotations visible through `Info` rather than a second planner.

That is also the boundary against source generation.
[Comptime](../concepts/comptime.md) evaluates closed value-producing programs
after normal type checking, and derives run as part of declaration checking and
may attach only validated member recipes. Neither becomes a way to emit
arbitrary source.
:::

### Provider inputs

Every provider on an owner receives the same immutable pre-merge `Info` view. It
contains the owner and interface type handles, ordered stored fields with
read/write handles, semantic identities, and opaque diagnostic references. It
contains no tokens, locations, comments, AST, CST, mutable compiler objects, or
previous provider output. `nupp.derive.claims(T, I)` asks whether a nominal type
writes or requests contract `I`, which lets mutually recursive derives plan
without depending on provider execution order.

A generic owner is planned once, not per instantiation. A type parameter exposes
its bound, or `unknown`, so providers cannot specialize for future concrete
arguments.

Providers run through the bounded comptime worker. Their sealed source and
reachable comptime helper closure travel in the module interface; they do not
remain runtime functions. A provider failure may return
`nupp.derive.error(message, reference, code)` to point at the owner or
contributing field without observing a filename or source position. The code is
optional and defaults to the generic provider diagnostic
[`NUPP2810`](diagnostics.md).

### Filesystem inputs

A provider that generates a recipe from a schema or other immutable project file
reads it with `nupp.derive.file`:

```nupp
comptime function M.derive(info: nupp.derive.Info): nupp.derive.Result<M.Inspect>
    local schema = nupp.derive.file("schemas/inspect.txt")
    return nupp.derive.implement {
        methods = {
            inspect = nupp.derive.forward {
                helper = nupp.derive.helper(M, "renderSchema"),
                arguments = {nupp.derive.constant(schema)},
            },
        },
    }
end
```

The path must be a string literal and remain within the consumer project root.
The compiler reads it before the isolated worker starts, fingerprints its bytes
with the provider input, and records it in the incremental dependency graph.
Changing the file invalidates only provider consumers, and watch mode observes
the canonical path and refuses to patch over changed generated state without a
restart. Missing files are diagnostics.

Providers have no general host I/O, so network resources, environment variables,
clocks, mutable tables, and hidden filesystem reads cannot silently enter a
cache or a [hot-reload](../guides/hot-reload.md) guarantee.

## Closed forwarding recipes

`nupp.derive.implement` returns instance methods and static functions. A bare
`Forward` fills an interface requirement and inherits its signature. A
`nupp.derive.member` supplies a function type built with `nupp.types` and its
parameter names, allowing a provider to add a member that is not declared by the
result interface.

```nupp
return nupp.derive.implement {
    methods = {
        inspect = nupp.derive.forward {
            helper = nupp.derive.helper(M, "renderRecord"),
            arguments = {
                nupp.derive.constant(names),
                nupp.derive.array(values),
            },
        },
    },
}
```

Both forms lower through `forward.v1`, which names one ordinary runtime helper
and supplies a closed argument list:

- `receiver()` passes the generated method receiver.
- `argument(name)` passes a named interface method parameter.
- `entry()` passes the derived type's private runtime schema entry.
- `field(fieldInfo)` directly reads one admitted stored field.
- `constant(value)` embeds a bounded quotable value.
- `array(arguments)` constructs a fresh array from argument recipes.

There are no nested calls, operators, branches, assignments, loops, arbitrary
member accesses, or source fragments in a forwarding recipe. Table-shaped
constants and arrays are fresh for each call, so mutation by one invocation
cannot affect the next.

The first version refuses overloaded requirements, interface defaults,
properties, setters, and metamethods. Those require separate versioned recipe
capabilities rather than silently widening `forward.v1`.

### Runtime helpers

Runtime behavior stays in ordinary exported Nupp functions. Helpers are type
checked at their declarations, and the generated call is checked again against
the interface-owned argument and result packs, ownership, effects, and
suspension contract. `forward.v1` refuses generic runtime helpers; a later
recipe version can admit them once symbolic helper identity and caching are
specified. A helper module becomes an ordinary runtime dependency of the
consumer even when the comptime provider itself would otherwise erase.

::: deepdive
Keeping behavior in the language makes arbitrary runtime control flow,
optimization, effects, diagnostics, and future generic helpers available without
turning them into a macro IR. A macro IR would have to grow its own version of
each of those, and every one would then be a second implementation to keep
agreeing with the first.

The generated wrapper is a semantic node the compiler may inline or sink when
ordinary optimization proves that safe. Such optimization is not part of the
provider contract, so a recipe cannot depend on it happening.
:::

::: seealso
- [annotations.md](annotations.md#built-in-annotations) for `@derive`, `@json`,
  and `@debug` beside the rest of the built-ins
- [comptime.md](../concepts/comptime.md) for the evaluation model a provider
  runs in
- [reflection.md](../concepts/reflection.md#runtime-reflection) for the type
  witnesses generated members are built on
- [diagnostics.md](diagnostics.md) for the codes a provider failure reports
:::
