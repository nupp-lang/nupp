# Declaration derives

`@derive` generates a closed set of checked members on a record. It is a
declaration-augmentation phase, not a text macro: it cannot add imports,
top-level declarations, modules, records, interfaces, or independently
nameable types.

```nupp
@derive(nupp.derive.Debug, nupp.derive.Default, nupp.derive.JSON)
local record User
    @json(name = "user_id")
    id: integer

    @default("anonymous")
    name: string

    tags: {string}
end

@derive(nupp.derive.From)
local record UserId
    value: integer
end

local user = nupp.default(User)
local id = nupp.into(42, UserId)
print(user:debug(), id.value, user:toJSON())
```

The four bundled comptime providers are:

- `nupp.derive.Debug`: `debug(self): string` and `nupp.Debug` conformance.
- `nupp.derive.Default`: static `default(): T` and `nupp.default(T)` support.
- `nupp.derive.From`: static `from(value): T` and `nupp.into(value, T)` support.
- `nupp.derive.JSON`: `toJSON`, static `fromJSON`, `fieldCodec`, and
  `nupp.data.json.JSONEncodable` conformance.

Generated members participate in normal member lookup, generic inference, and
interface checking. A written member of the same name is a compile-time
conflict. Stacked `@derive` applications combine, but a provider cannot be
requested twice.

They are ordinary exported `@comptime` functions implemented in
`src/nupp/derive.nupp`; the compiler has no provider-name or operation switch
for them. All four travel through the same sealed comptime worker, immutable
`Info`, versioned result envelope, cache and recipe lowering used by package
providers.
Their schema configuration (`@debug`, `@default`, and `@json`) is included in
the semantic annotations visible through `Info`; it is not a second planner.

## Package providers

A package may export a derive provider as an `@comptime` function. Its exact
signature names the one existing interface it implements:

```nupp
@comptime
function M.derive(info: nupp.derive.Info): nupp.derive.Result<M.Inspect>
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

Applying the provider also claims `M.Inspect`. An equal written `is
inspect.Inspect` is redundant and coalesced. Interface defaults are inherited
normally and associated requirements are checked normally. A provider can fill
a bodyless callable requirement or declare a new function member with a closed
comptime-built signature. Generic, variadic, overloaded, and effectful provider
declarations are not part of the first recipe version.

Every provider on an owner receives the same immutable pre-merge `Info` view.
It contains the owner and interface type handles, ordered stored fields with
read/write handles, semantic identities, and opaque diagnostic references. It
contains no tokens, locations, comments, AST, CST, mutable compiler objects, or
previous provider output. `nupp.derive.claims(T, I)` asks whether a nominal type
writes or requests contract `I`, which lets mutually recursive derives plan
without depending on provider execution order.

A generic owner is planned once, not per instantiation. A type parameter
exposes its bound, or `unknown`, so providers cannot specialize for future
concrete arguments.

Providers run through the bounded comptime worker. Their sealed source and
reachable comptime helper closure travel in the module interface; they do not
remain runtime functions. A provider failure may return
`nupp.derive.error(message, reference, code)` to point at the owner or
contributing field without observing a filename or source position. The code
is optional and defaults to the generic provider diagnostic `NUPP2810`.

## Closed forwarding recipes

`nupp.derive.implement` returns instance methods and static functions. A bare
`Forward` fills an interface requirement and inherits its signature. A
`nupp.derive.member` supplies a function type built with `nupp.types` and its
parameter names, allowing a provider to add a member that is not declared by
the result interface. Both forms lower through `forward.v1`, which names one
ordinary runtime helper and supplies a closed argument list:

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

Keeping behavior in the language makes arbitrary runtime control flow,
optimization, effects, diagnostics, and future generic helpers available
without turning them into a macro IR. The generated wrapper is a semantic node
the compiler may inline or sink when ordinary optimization proves that safe;
such optimization is not part of the provider contract.

## Debug

`debug(self): string` renders a value the way the declaration reads, so what
comes back names the record and its fields in declaration order.

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

A field annotation decides what a field contributes. `redact` keeps the name and
replaces the value, which is what a secret wants; `skip` removes the field from
the output entirely.

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

## Default

`Default` generates a static `default(): T`, which `nupp.default(T)` also
reaches. Every field answers for itself: optionals give nil, booleans false,
numerics zero, strings the empty string, and arrays and maps a fresh table each
call.

```nupp
@derive(nupp.derive.Debug, nupp.derive.Default)
local record Settings
    name: string
    retries: integer
    verbose: boolean
    timeout: number?
    tags: {string}
end

print(nupp.default(Settings):debug())
```

```text
Settings { name = "", retries = 0, verbose = false, timeout = nil, tags = {} }
```

`@default(value)` supplies a compile-time literal instead, and a nominal field
uses its own derived `default()`, so one call fills a whole graph.

```nupp
@derive(nupp.derive.Debug, nupp.derive.Default)
local record Settings
    name: string
    retries: integer
end

@derive(nupp.derive.Debug, nupp.derive.Default)
local record Server
    @default("localhost")
    host: string
    @default(8080)
    port: integer
    settings: Settings
end

print(Server.default():debug())
```

```text
Server { host = "localhost", port = 8080, settings = Settings { name = "", retries = 0 } }
```

A mutable literal table is copied for every call, so two defaults never share
one. Tuples and finite shapes default member by member.

A required recursive graph is rejected, because it has no bottom: a `Node` whose
`next: Node` is not optional would have to build forever. Make the recursive
edge optional, or give it an explicit terminating default.

## From

`From` is the unambiguous newtype conversion: a static `from(value): T`, which
`nupp.into(value, T)` also reaches. Its record must have exactly one stored
field and no written constructor, so there is never a question of which field a
value lands in.

```nupp
@derive(nupp.derive.Debug, nupp.derive.From)
local record UserId
    value: integer
end

@derive(nupp.derive.Debug, nupp.derive.From)
local record Email
    value: string
end

local id = nupp.into(42, UserId)
local mail = Email.from("ada@example.com")
print(id:debug(), mail:debug())
```

```text
UserId { value = 42 }	Email { value = "ada@example.com" }
```

What that buys is a parameter that cannot be filled by the wrong integer:

```nupp
@derive(nupp.derive.From)
local record UserId
    value: integer
end

local function findUser(id: UserId): string
    return "user " .. tostring(id.value)
end

return findUser(nupp.into(7, UserId))
```

It does not perform structural record conversion, and it does not validate.
A conversion that can fail stays an ordinary function returning `T?, string?`.

## JSON

`JSON` generates `toJSON`, a static `fromJSON`, a `fieldCodec`, and
`nupp.data.json.JSONEncodable` conformance. Encoding is deterministic: record and
shape fields follow declaration order and string map keys sort by byte order, so
the same value always produces the same bytes.

```nupp
@derive(nupp.derive.JSON, nupp.derive.Debug)
local record User
    @json(name = "user_id")
    id: integer
    name: string
end

local user = new User(id = 7, name = "ada")
print(user:toJSON())

local decoded = User.fromJSON('{"user_id": 7, "name": "ada"}')
print(decoded and decoded:debug())
```

```text
{"user_id":7,"name":"ada"}
User { id = 7, name = "ada" }
```

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
print(user:toJSON())
print(select(2, User.fromJSON(user:toJSON())))
```

```text
{"id":7}
$.tags: required field is absent
```

Use `omit` with a default when a field should disappear from both directions.

### Schemas

Booleans, strings, finite numbers, exactly representable integer widths,
optionals, arrays, tuples, string-keyed maps, finite shapes, and records
deriving JSON are all supported. `int64` and `uint64` are rejected, because a
JSON number cannot round-trip their full range, and the erased `integer` type is
checked against the safe interval at run time.

Strings must be valid UTF-8, and a cycle or nesting beyond 128 containers fails
with the JSON path that reached it. Encoding neither reads nor mutates cjson
settings.

Decoding uses a private `nupp.data.json.newJSON()` with array metatables
disabled, depth 128, and invalid numbers disabled. Generated validation checks
the raw value before the record is returned, so mutating `nupp.data.json` or
another JSON instance cannot alter a derived codec.

## Relationship to comptime

Comptime evaluates closed value-producing programs after normal type checking.
Derives run as part of declaration checking and may attach only validated
member recipes. The bundled Debug, Default, From, and JSON providers use that
same public mechanism; neither derives nor comptime become arbitrary source
generation.

## Next

- [annotations.md](annotations.md): the field annotations each provider reads.
- [reflection.md](concepts/reflection.md): the descriptor a generator reads instead.
