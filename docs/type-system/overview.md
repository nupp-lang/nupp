# Type system

Nupp is gradually typed: anything unannotated or unresolvable is `any` and
checks silently, so an untyped LuaJIT program is already a valid Nupp program.
An annotation is what turns checking on, one declaration at a time.

```nupp:playground
local total = 1
total = total / 2

local count: integer = 1
count = count / 2 -- NUPP2001: number is not a integer
```

## Inference

The checker infers a type where an initializer settles it, and nowhere else.

| Position | Inferred |
| --- | --- |
| Local from its initializer | Yes, and a mutable one widens |
| Function parameter | No; an unannotated parameter is `any` |
| Function result | No; the body's returns go unchecked |
| Short-function body | Yes, one inferred result |
| Unknown global | No; `any`, silently |

A function with no result annotation is not checked against its `return`
statements at all, and its calls produce `any`:

```nupp
local function area(w, h)
    return w * h
end

local label: string = area(2, 3) -- checks clean
```

Annotating the result is what starts checking both ends:

```nupp
local function area(w: number, h: number): number
    return w * h
end

local label: string = area(2, 3) -- NUPP2001: number is not a string
```

## Mutable locals widen

An unannotated mutable binding loosens, so that ordinary Lua keeps checking:

```nupp
local i = 1
i = i / 2

local m = {a = 1}
m.b = 2

local n = nil
n = {}
print(n.field)
```

That is every case. A literal type on a mutable binding collapses to its base,
`integer` widens further to `number`, a shape built from a table literal
collapses to `table`, and `nil` becomes `any`. Only a mutable literal
initializer widens, so a shape returned by a call keeps its type.

A `const` binding cannot be reassigned, so it keeps the literal it was given:

```nupp
const tag = "ready" -- the literal type "ready"
```

An annotation keeps exactly the type you wrote, on a mutable binding too:

```nupp
local j: integer = 1
j = j / 2 -- NUPP2001: number is not a integer

local shaped: {
    a: number
} = {a = 1}
shaped.b = 2 -- NUPP2004: no field "b" in {a: number}
```

::: deepdive
Widening is the price of the first rule on this page. `local i = 1` in ordinary
Lua is a counter, not the number one, and a checker that read the initializer
literally would report the second line of every loop anybody already wrote. The
alternative was inferring the literal and asking for `local i: number = 1` at
each site, which makes the annotation the default and gradual typing a slogan.
Widening applies only where there is no annotation and no `const`, so both
narrower readings stay one word away.
:::

## Strict floor

Strict adds two rules on top of what every file is checked for:

- `NUPP2105`: unknown variable, for a name no project file answers to.
- `NUPP2106`: an exported declaration needs a type annotation, so nothing
  untyped crosses a module boundary.

Everything else is checked identically either way. Which files hold that floor
is decided by their extension, so a file says what it is where anyone reading
it can see it:

| Extension | Floor | Means |
| --- | --- | --- |
| `.nupp` | strict | Ordinary Nupp. |
| `.g.nupp` | gradual | The typed syntax, without the floor. |
| `.d.nupp` | gradual | Describes an interface somebody else implements. |
| `.lua` | gradual | Plain Lua, and the typed layer is refused there. |

`.g.nupp` is the opt-out, and it is a whole file at a time on purpose: a
per-declaration escape would be a second way to say `any`, which the language
already has. The module name drops the marker, so `models.g.nupp` is the module
`models` and `require("models")` finds it. A file can therefore change layer
without anything that requires it noticing.

`.d.nupp` is exempt because a declaration file describes foreign code. LuaJIT's
`string.buffer.encode(v: any): string` really does take any Lua value, and no
annotation written here changes what LuaJIT accepts.

`--strict` overrides the lot, holding every file to the floor including the
`.g.nupp` ones. That is the tool for finding out what adopting one would cost:

```bash
nupp check --strict
```

## Gradual escape hatches

`any` is compatible with everything in both directions. Reading a field of
`any` gives `any`; calling it gives `any` with no arity or argument checks. It
swallows unions too, so `any | string` is `any`:

```nupp
local config: any = require("settings")
print(config.missing.deeper()) -- checks clean
```

`as` is an assertion the checker trusts completely, in both directions, and it
erases at code generation:

```nupp
local n = ("5" as any) as number -- checks clean
```

Use `as` where you know something the checker cannot. It reports nothing when
you are wrong.

Where a value is genuinely untyped rather than deliberately unchecked, reach
for `unknown` instead. Everything fits into it and it fits nowhere else, so
each use has to narrow or cast first. See [`unknown`, the top
type](primitives.md#unknown-the-top-type) for more information.

## Deliberate unsoundness

Four rules are unsound on purpose, because the sound version rejects too much
ordinary Lua:

```nupp
local ints: {integer} = {1, 2}
local nums: {number} = ints -- accepted: arrays are covariant
nums[1] = 1.5
```

That last line stores a non-integer into a `{integer}`, and nothing reports it.

- **Arrays are covariant.** `{integer}` is accepted where `{number}` is wanted.
- **Shape fields are covariant**, not invariant, even though they are mutable.
- **`table` is gradual in both directions.** Every table-shaped type is a
  `table`, and a `table` may be used where any of them is wanted. It is closer
  to "`any`, for tables" than to a top type.
- **A declared `is` edge is trusted rather than proved.** If a record says
  `is Closeable`, it satisfies `Closeable` even before a runtime registrar has
  filled the members in.

Each is a place where the checker chose compatibility over proof. See [`is` is
a claim, not a proof](interfaces.md#is-is-a-claim-not-a-proof) for what a
declared edge promises and what it does not.

## Type-system guides

One page per idea, in the order they build on each other:

- [Primitive types](primitives.md): the builtin names, unions, optionals,
  collections, and aliases.
- [Records and structs](records.md): nominal tables and FFI cdata.
- [Affine types](affine-types.md): compile-time type construction, exact
  cleanup identities, transfer-only values, and capability-preserving generics.
- [Ownership](ownership.md): moves, borrows, aggregates, pinning, and lexical
  destruction.
- [Interfaces](interfaces.md): structural satisfaction, `is`, and metamethods.
- [Refinements](refinements.md): the `satisfies` test a declaration carries.
- [Property capabilities](properties.md): independent read and write views.
- [Unions](unions.md): literal sets, tagged unions, and exhaustiveness.
- [Intersections](intersections.md): capability composition and provable
  emptiness.
- [Overloads and overrides](overloads.md): callable intersections, separate
  method bodies, interface defaults, and constructors.
- [Generics](generics.md): type parameters, inference, and bounds.
- [Comptime types](type-level-computation.md): member transforms, const
  parameters, matching, template literal types, and guarded recursion.
- [Type packs](packs.md): heterogeneous variadics, Lua value-list adjustment,
  protected calls, and coroutine protocols.
- [Associated types](associated-types.md): the types an interface leaves for
  its implementors to name.
- [Narrowing](narrowing.md): what proves what, and what does not.

## FAQ

### When should a value be `unknown` instead of `any`?

Reach for `any` when the code is deliberately unchecked, such as a boundary
that has not been annotated yet. Reach for `unknown` when the value genuinely
has no known type, such as a JSON decode or a `pcall` result, because it forces
every later use to narrow or cast. See [`unknown`, the top
type](primitives.md#unknown-the-top-type) for the tests that reach it.

### Are Nupp types nominal or structural?

Both, and the declaration decides which. A `record` and a `struct` are nominal,
so two with identical fields are different types, while an interface and a
table shape are satisfied structurally by anything carrying the members. See
[satisfaction is structural](interfaces.md#satisfaction-is-structural) for what
that admits.

### Does anything survive to run time?

Almost nothing. Annotations, aliases, interfaces, and `as` are erased, so
generated Lua carries no type tags; `record`, `struct`, and interface default
implementations emit the tables that ordinary Lua would have written by hand.
See [strictness.md](../concepts/strictness.md) for the two exceptions.

::: seealso
- [strictness.md](../concepts/strictness.md) for the gradual typing model and
  what adopting the strict floor costs
- [modules.md](../concepts/modules.md) for where a declaration lives and how
  another module sees it
- [diagnostics.md](../reference/diagnostics.md) for every code this section
  names
:::
