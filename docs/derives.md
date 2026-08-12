# Declaration derives

`@derive` generates a closed set of checked members on a record. It is a
declaration-augmentation phase, not a text macro: it cannot add imports,
top-level declarations, modules, or independently nameable types.

```nupp
@derive(Debug, Default, JSON)
local record User
    @json(name = "user_id")
    id: integer

    @default("anonymous")
    name: string

    tags: {string}
end

@derive(From)
local record UserId
    value: integer
end

local user = nupp.default(User)
local id = nupp.into(42, UserId)
print(user:debug(), id.value, user:toJSON())
```

The four built-in providers are:

- `Debug`: `debug(self): string` and `nupp.Debug` conformance.
- `Default`: static `default(): T` and `nupp.default(T)` support.
- `From`: static `from(value): T` and `nupp.into(value, T)` support.
- `JSON`: `toJSON`, static `fromJSON`, `fieldCodec`, and
  `nupp.data.JSONEncodable` conformance.

Generated members participate in normal member lookup, generic inference, and
interface checking. A written member of the same name is a compile-time
conflict. Stacked `@derive` applications combine, but a provider cannot be
requested twice.

## Debug

`debug(self): string` renders a value the way the declaration reads, so what
comes back names the record and its fields in declaration order.

```nupp
@derive(Debug)
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
@derive(Debug)
local record Tag
    name: string
end

@derive(Debug)
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
@derive(Debug)
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
@derive(Debug, Default)
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
@derive(Debug, Default)
local record Settings
    name: string
    retries: integer
end

@derive(Debug, Default)
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
@derive(Debug, From)
local record UserId
    value: integer
end

@derive(Debug, From)
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
@derive(From)
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
`nupp.data.JSONEncodable` conformance. Encoding is deterministic: record and
shape fields follow declaration order and string map keys sort by byte order, so
the same value always produces the same bytes.

```nupp
@derive(JSON, Debug)
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
@derive(JSON)
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
@derive(JSON)
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

Decoding uses a private `nupp.data.newJSON()` with array metatables disabled,
depth 128, and invalid numbers disabled. Generated validation checks the raw
value before the record is returned, so mutating `nupp.data` or another JSON
instance cannot alter a derived codec.

## Relationship to comptime

Comptime evaluates closed value-producing programs after normal type checking.
Derives run as part of declaration checking and may attach only their
compiler-owned member recipes. They can share reflection and materialization
infrastructure, but neither turns comptime into arbitrary source generation.

## Next

- [annotations.md](annotations.md): the field annotations each provider reads.
- [reflection.md](concepts/reflection.md): the descriptor a generator reads instead.
