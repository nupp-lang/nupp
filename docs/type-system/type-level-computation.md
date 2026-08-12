# Type-level computation

Nupp has one general compile-time programming language: ordinary Nupp inside
`@comptime` functions. A comptime function may accept compiler-only `type` and
`typepack` handles and return a structural type or value pack. Calling such a
function in type position executes it while the program is checked and emits no
runtime function or data.

```nupp
@comptime
local function Optional(T: type): type
    return nupp.types.optional(T)
end

local value: Optional(string) = nil
```

Type functions generate types, not declarations. They may construct structural
shapes, tuples, maps, functions, unions, intersections, wrappers, and packs, or
return an existing nominal type. They cannot create a record, interface, method,
module member, name, or runtime identity.

## Inspection and construction

Type handles are opaque and immutable. `nupp.types.describe(T)`, `kind`,
`elements`, `fields`, `readKeys`, `writeKeys`, `readAt`, and `writeAt` expose
checked semantic information without exposing mutable checker state. Builders
such as `literal`, `optional`, `array`, `tuple`, `map`, `shape`, `union`,
`intersection`, `pointer`, `carray`, `constof`, `function_`, and `pack` produce
validated handles.

```nupp
@comptime
local function DeepElement(T: type): type
    while nupp.types.kind(T) == "array" do
        T = nupp.types.elements(T)[1]
    end
    return T
end

local leaf: DeepElement({{{integer}}}) = 42
```

`nupp.types.error(message)` deliberately rejects the type application. It is
distinct from an evaluator crash or timeout and reports the authored message at
the application with a bounded comptime call trace.

## Closed and generic calls

A call whose type, pack, and scalar arguments are concrete executes immediately.
An application containing a type parameter or const binder remains an open type
term. Generic substitution executes it as soon as inference makes every argument
concrete.

```nupp
@comptime
local function Arguments(Kind: type): typepack
    local info = nupp.types.describe(Kind)
    if info.kind == "literal" and info.value == "pair" then
        return nupp.types.pack({nupp.types.string, nupp.types.number})
    end
    return nupp.types.pack({}, nupp.types.any)
end

local function apply<Kind is string>(
    kind: Kind,
    ...: unpackof Arguments(Kind)
): string
    return kind
end
```

`type<Bound>` constrains a generated result. Until an open call closes, ordinary
type consumers may use only facts promised by that bound. Nupp does not
symbolically execute arbitrary comptime branches over unresolved types.

## Direct finite operators

Small, locally readable type operations remain syntax. `keyof T` and
`writekeyof T` enumerate readable and writable keys. `T.[K]` reads a member type
and `writeof T.[K]` gives the accepted write type. Mapped structural shapes,
template construction, const parameters, associated-type projections, and
`unpackof` are also retained.

```nupp
local type Events<T> = {
    readonly [K in keyof T as `${K}Changed`]: function(value: T.[K]): nil
}
```

These bounded operators are preferred when they state the transformation more
clearly than a function and builder calls. User-authored branching, iteration,
parsing, and recursion belong in comptime functions.

## Const parameters

Const parameters admit only `string`, `boolean`, and exactly representable
`integer` values. They erase at runtime. Integer const expressions admit `+`,
`-`, `*`, `//`, `%`, and comparisons.

```nupp
local record Matrix<T, const Rows: integer, const Columns: integer>
    values: T[Rows * Columns]
end
```

## `string.format`

The prelude types `string.format` with a comptime scanner. Literal formats get
exact argument arity and conversion checks; a broad runtime `string` retains a
gradual `...any` tail.

```nupp
local count = string.format("%s has %d messages", "Ada", 3)
```

Supported conversions match LuaJIT's bounded formatting surface. Invalid,
missing, surplus, and mismatched arguments report on the ordinary call. This is
implemented through the same type-function mechanism available to user code,
not a format-specific checker branch.

## Limits and isolation

Type functions run in the isolated comptime worker with deterministic iteration,
step, call-depth, wall-clock, memory, protocol, graph-size, and member limits.
Results cross the worker boundary as validated structural blueprints; they
cannot forge nominal identity or escape into generated Lua. Recursive algorithms
use ordinary comptime calls or loops and are governed by those limits.

## Next

- [packs.md](packs.md): value sequences and `unpackof`.
- [generics.md](generics.md): type, pack, and const parameters.
- [associated-types.md](associated-types.md): declaration-owned type answers.
