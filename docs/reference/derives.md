---
order: 680
title: Declaration derives
---

`nupp.derive.Debug` adds a checked `debug` method to a record or struct.
Packages publish additional providers through the same recipe API.

```nupp:playground
@derive(nupp.derive.Debug)
local record User
    id: integer
    name: string = "anonymous"
    tags: {string} = {}
end
local user = new User(id = 1)
print(user:debug())
```

Applying a provider is a declaration-augmentation phase, not a text macro: it
cannot add imports, top-level declarations, modules, records, interfaces, or
independently nameable types. `nupp.derive.Debug` adds `debug(self): string`
and `nupp.Debug` conformance. Serialization uses explicit
[bindings](../learn/runtime/data/serde.md) and needs no derive.

[`nupp.events.Event`](#event) is applied the same way and marks a record or a
fixed-layout struct as an event a [](nupp.events) source constructs and
delivers.

Generated members participate in normal member lookup, generic inference, and
interface checking. A written member of the same name is a compile-time
conflict. Stacked `@derive` applications combine, but a provider cannot be
requested twice. See [annotations.md](annotations.md#derive) for where `@derive`
sits among the built-in annotations.

## Debug

`debug(self): string` renders a record or fixed-layout struct the way the
declaration reads, so what comes back names the declaration and its fields in
declaration order. The method forwards the declaration witness to the value
visitor, which caches its Debug policy on first use.

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

Debug owns its selection policy. Skipped and redacted fields are never read,
and a field that Debug can render need not have a JSON representation. A caller
can also render an explicit binding or append to an existing Buffer:

```nupp
local serde = require("nupp.serde")
local debug = require("nupp.serde.debug")
local struct Vec2
    x: float
    y: float
end
local binding = serde.binding(Vec2)
local output = nupp.text.newBuffer()
debug.write(binding, new Vec2(1.25, 2.5), output)
assert(output:tostring() == "Vec2 { x = 1.25, y = 2.5 }")
```

## Event

`nupp.events.Event` records an event's name and representation and asks the
compiler for the declaration's initializer, so a source can construct the event
into storage it already holds. It generates no members; what it adds is the
`nupp.events.Emittable` contract that every `Type<E>` an event source takes is
bounded by.

```nupp
local events = require("nupp.events")

@derive(events.Event)
@event(name = "combat.Damage")
local record Damage
    amount: number
    source: integer
    kind: string = "physical"
end

local bus: events.MessageBus<integer> = events.newMessageBus()
bus:observe(7, Damage, |event| -> print(event.kind))
bus:emit(7, Damage, amount = 10, source = 3)
```

`@event(name = "...")` sets the name `events.name(Damage)` returns; the
declaration's own name is the default. The name is what something outside the
program pins, such as a debug protocol, which is why it is written rather than
derived from a path that a refactor would move.

The derive admits a concrete record or a fixed-layout struct with one
construction contract. It refuses a declaration with several constructors, a
constructor that lets `self` escape or moves an owned parameter into a field,
an affine field, and a generic owner, because none of those can run against
storage that is reused: the next lease would find the reference, the moved
obligation, or the shared identity already there.

## Package providers

A package may export a derive provider as a `@comptime function`. Its exact
signature names the one existing interface it implements:

```nupp:fragment
@comptime
function M.derive(info: nupp.derive.Info): nupp.derive.Result<M.Inspect>
    -- inspect info and return a closed recipe
end
```

In a declared module, write `@comptime export function derive(...)` instead of
qualifying the function through a module table. Exported annotation declarations
may accompany the provider and remain compile-time metadata, not runtime values.

A consumer applies the resolved exported symbol, not a runtime function value:

```nupp:fragment
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
`Debug` is an exported `@comptime function` in `src/nupp/derive.nupp`.
It uses the same comptime worker, immutable `Info`, result envelope, cache, and
recipe lowering as package providers. Its `@debug` configuration is part of
the semantic annotations visible through `Info`.

That is also the boundary against source generation.
[Comptime](../learn/language/comptime.md) evaluates closed value-producing programs
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

`Info.name` names the declaration. `Info.qualifiedName` combines its module and
declaration path, giving providers a default identity without a source filename.
Packages that persist this identity should offer an explicit override: renaming
a declaration or moving it to another module changes its qualified name.

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

### Initializers

A provider may ask for the owner's initializer with `initializer = true` beside
`methods`, `statics`, and `data`. The compiler then mints the declaration's
constructor body, or its field list when it declares none, as a hidden member
taking the instance first: `initializer(storage, ...)` fills storage the caller
already holds and returns it, and `new` allocates and calls the same body. The
runtime reaches it through `nupp.derive.initializer(Type)`. A field-list
initializer applies a field default where its argument is nil, which is the one
place that can, since a positional call never passes through the checker's
default filling.

The compiler refuses the request on a declaration whose body could notice the
reuse: several constructors, a constructor that lets `self` escape or moves a
`takes` parameter into a field, an affine field, or a generic owner, each
reported as `NUPP2810` on the application.

### Filesystem inputs

A provider that generates a recipe from a schema or other immutable project file
reads it with `nupp.derive.file`:

```nupp:fragment
@comptime
function M.derive(info: nupp.derive.Info): nupp.derive.Result<M.Inspect>
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
cache or a [hot-reload](../learn/projects/hot-reload.md) guarantee.

## Closed forwarding recipes

`nupp.derive.implement` returns instance methods and static functions. A bare
`Forward` fills an interface requirement and inherits its signature. A
`nupp.derive.member` supplies a function type built with `nupp.types` and its
parameter names, allowing a provider to add a member that is not declared by the
result interface. Parameter names are non-empty and unique, and every recipe
array is dense.

```nupp:fragment
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
- `field(fieldInfo)` directly reads one readable stored field.
- `constant(value)` embeds a bounded quotable value.
- `witness(annotationType(argument))` passes the `Type<T>` witness named by an
  `@ref` annotation argument from the owner or one of its fields.
- `array(arguments)` constructs a fresh array from argument recipes.

`annotationType` accepts only a `kind = "type"` argument taken from the
provider's immutable `Info`. The referenced record remains typed across the
comptime boundary instead of being reduced to a name string.

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
- [annotations.md](annotations.md#built-in-annotations) for `@derive`,
  and `@debug` beside the rest of the built-ins
- [comptime.md](../learn/language/comptime.md) for the evaluation model a provider
  runs in
- [reflection.md](../learn/language/reflection.md#runtime-reflection) for the type
  witnesses generated members are built on
- [diagnostics.md](diagnostics.md) for the codes a provider failure reports
:::
