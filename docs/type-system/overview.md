# Type system

Nupp is gradually typed. Anything unannotated or unresolvable is `any` and
checks silently, so an untyped LuaJIT program is a valid Nupp program that
reports nothing. Annotations are what turn checking on, one declaration at a
time.

That sentence is the design. Everything below follows from it.

```nupp
local i = 1
i = i / 2

local m = {a = 1}
m.b = 2
```

## Inference

| Position | Inferred? |
| --- | --- |
| Local from its initializer | Yes; mutable bindings widen - see below |
| Function parameters | No; an unannotated parameter is any |
| Function return types | No; the body's returns go unchecked |
| Short-function body | Yes, one inferred result |
| Unknown global | any, silently |

A function with no return annotation is not checked against its `return`
statements at all. Annotating the return is what starts checking them.

## Mutable locals widen

This is the rule people trip over. A mutable binding with no annotation
deliberately loosens, so that ordinary Lua keeps working:

```nupp:playground
local i = 1
i = i / 2 -- fine: integer widened to number

local m = {a = 1}
m.b = 2 -- fine: the shape widened to table

local n = nil
n = {}
print(n.field) -- fine: nil widened to any
```

A `const` binding keeps an inferred literal type, and an annotation keeps
exactly the type you wrote:

```nupp
const tag = "ready" -- the literal type "ready"
```

An annotation can also keep a narrower type on a mutable binding:

```nupp
local j: integer = 1
j = j / 2 -- NUPP2001: number is not a integer

local shaped: {
    a: number
} = {a = 1}
shaped.b = 2 -- NUPP2004: no field "b" in {a: number}
```

The four widening cases are: a literal type on a mutable binding collapses to
its base, `integer` widens further to `number`, a shape built from a table
literal collapses to `table`, and `nil` becomes `any`. A shape *returned by a
call* keeps its type, because only mutable literal initializers widen.

The practical reading: annotate when you want the constraint, leave it off when
you want the Lua behavior. Both are supported positions.

## Strict floor

Strict adds exactly two things:

- **NUPP2105**: unknown variable, for a name no project file answers to.
- **NUPP2106**: an exported declaration needs a type annotation, so nothing
  untyped crosses a module boundary.
Everything else is checked identically either way.

Which files hold that floor is decided by their extension, so a file says what
it is where anyone reading it can see it:

| Extension | Floor | What it means |
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

`any` is compatible with everything in both directions. Reading a field of `any`
gives `any`; calling it gives `any` with no arity or argument checks. It also
swallows unions, so `any | string` is `any`.

There is no `unknown` and no `never`, and no bottom type of any kind.
Subtracting every member of a union leaves the union alone rather than
producing an empty type.

`as` is an assertion the checker trusts completely, in both directions:

```nupp
local n = ("5" as any) as number -- checks clean
```

It erases at code generation. Use it where you know something the checker
cannot; it will not warn you when you are wrong.

## Deliberate unsoundness

Four rules are unsound on purpose, because the sound version rejects too much
ordinary Lua:

- **Arrays are covariant.** `{integer}` is accepted where `{number}` is wanted.
- **Shape fields are covariant**, not invariant, even though they are mutable.
- **`table` is gradual in both directions.** Every table-shaped type is a
  `table`, and a `table` may be used where any of them is wanted. It is closer
  to "`any`, for tables" than to a top type.
- **A declared `is` edge is trusted rather than proved.** If a record says
  `is Closeable`, it satisfies `Closeable` even before a runtime registrar has
  filled the members in.

Each is a place where the checker chose compatibility. Knowing which four they
are is more useful than pretending they do not exist.

## Type-system guides

One page per idea, in the order they build on each other:

- [Primitive types](primitives.md): the builtin names, unions, optionals,
  collections, and aliases.
- [Records and structs](records.md): nominal tables and FFI cdata.
- [Affine types](affine-types.md): compile-time type construction, exact cleanup
  identities, transfer-only values, and capability-preserving generics.
- [Ownership](ownership.md): moves, borrows, aggregates, pinning, and lexical
  destruction.
- [Interfaces](interfaces.md): structural satisfaction, `is`, and metamethods.
- [Property capabilities](properties.md): independent read and write views.
- [Unions](unions.md): literal sets, tagged unions, and exhaustiveness.
- [Intersections](intersections.md): capability composition and provable
  emptiness.
- [Overloads and overrides](overloads.md): callable intersections, separate
  method bodies, interface defaults, and constructors.
- [Generics](generics.md): type parameters, inference, and bounds.
- [Comptime types](type-level-computation.md): member transforms,
  const parameters, matching, template literal types, and guarded recursion.
- [Type packs](packs.md): heterogeneous variadics, Lua value-list adjustment,
  protected calls, and coroutine protocols.
- [Narrowing](narrowing.md): what proves what, and what does not.

For where a declaration lives and how modules see it, read
[declarations and modules](../concepts/declarations.md).
