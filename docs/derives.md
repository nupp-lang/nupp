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

| Provider | Generated surface |
| --- | --- |
| `Debug` | `debug(self): string` and `nupp.Debug` conformance |
| `Default` | static `default(): T` and `nupp.default(T)` support |
| `From` | static `from(value): T` and `nupp.into(value, T)` support |
| `JSON` | `toJSON`, static `fromJSON`, `fieldCodec`, and `nupp.data.JSONEncodable` conformance |

Generated members participate in normal member lookup, generic inference, and
interface checking. A written member of the same name is a compile-time
conflict. Stacked `@derive` applications combine, but a provider cannot be
requested twice.

## Debug

Debug output follows declaration order. Strings are quoted, map keys are
sorted, and recursive runtime tables render as `<cycle>`. Field annotations
may hide or redact values:

```nupp
@derive(Debug)
local record Credentials
    user: string
    @debug(redact = true)
    password: string
    @debug(skip = true)
    cache: any
end
```

## Default

Optionals default to nil; booleans to false; numerics to zero; strings to an
empty string; and arrays and maps to fresh empty tables. Tuples and finite
shapes default member by member. A nominal field uses its own derived
`default()`. `@default(value)` supplies a literal compile-time value and mutable
literal tables are copied for every call.

Required recursive default graphs are rejected. Make the recursive edge
optional or give it an explicit terminating default.

## From

`From` is deliberately the unambiguous newtype conversion. Its record must
have exactly one stored field and no written constructor. It does not perform
structural record conversion or validation; fallible conversions remain
ordinary functions.

## JSON

JSON encoding is direct and deterministic: record and shape fields use
declaration order, string map keys are sorted by byte order, strings must be
valid UTF-8, and cycles or nesting beyond 128 containers fail with a JSON path.
Encoding does not use or mutate cjson settings.

Decoding uses a private `nupp.data.newJSON()` configured with array metatables
disabled, depth 128, and invalid numbers disabled. Generated validation checks
the raw value before returning the record. Mutating `nupp.data` or another JSON
instance cannot alter a derived codec.

Record options:

- `@json(unknown = "reject")`, the default, rejects unknown keys.
- `@json(unknown = "ignore")` ignores unknown keys.

Field options:

- `name = "wire_name"` renames the key.
- `omit = true` removes the field in both directions and requires a default.
- `omitEmpty = true` omits nil, false, empty strings, and empty tables only
  while encoding.

Supported schemas include booleans, strings, finite numbers, exactly
representable integer widths, optionals, arrays, tuples, string-keyed maps,
finite shapes, and records deriving JSON. `int64` and `uint64` are rejected
because JSON numbers cannot exactly round-trip their full range. The erased
`integer` type is checked against the safe interval at runtime.

`fromJSON` returns `T?, string?`. Errors name the failing path, for example
`$.user_id: expected integer in range` or `$: unknown field "user_nmae"`.

## Relationship to comptime

Comptime evaluates closed value-producing programs after normal type checking.
Derives run as part of declaration checking and may attach only their
compiler-owned member recipes. They can share reflection and materialization
infrastructure, but neither turns comptime into arbitrary source generation.
