# Type system

Nupp is gradually typed. Anything unannotated or unresolvable is `any` and
checks silently, so an untyped LuaJIT program is a valid Nupp program that
reports nothing. Annotations are what turn checking on, one declaration at a
time.

That sentence is the design. Everything below follows from it.

## What is inferred, and what is not

```
 Position                     Inferred?
 ───────────────────────────  ────────────────────────────────────
 Local from its initializer   Yes, but widened — see below
 Function parameters          No; an unannotated parameter is any
 Function return types        No; the body's returns go unchecked
 Short-function body          Yes, one inferred result
 Unknown global               any, silently
```

A function with no return annotation is not checked against its `return`
statements at all. Annotating the return is what starts checking them.

## Unannotated locals widen

This is the rule people trip over. A binding with no annotation deliberately
loosens, so that ordinary Lua keeps working:

```nupp
local i = 1
i = i / 2            -- fine: integer widened to number

local m = {a = 1}
m.b = 2              -- fine: the shape widened to table

local n = nil
n = {}
print(n.field)       -- fine: nil widened to any
```

A binding with an annotation keeps exactly what you wrote:

```nupp
local j: integer = 1
j = j / 2            -- NUPP2001: number is not a integer

local shaped: {a: number} = {a = 1}
shaped.b = 2         -- NUPP2004: no field "b" in {a: number}
```

The four widenings are: a literal type collapses to its base, `integer` widens
further to `number`, a shape built from a table literal collapses to `table`,
and `nil` becomes `any`. A shape *returned by a call* keeps its type — only
literals widen.

The practical reading: annotate when you want the constraint, leave it off when
you want the Lua behaviour. Both are supported positions.

## `--strict`

Strict mode adds exactly three things:

- **NUPP2105** — unknown variable, for a name no project file answers to.
- **NUPP2106** — an exported declaration needs a type annotation, so nothing
  untyped crosses a module boundary.
- **NUPP2503** — the `lossy-narrowing` lint, on a narrow integer annotation
  initialized from a wider numeric type. This lint is unreachable without
  strict mode.

Everything else is checked identically either way. `strict = true` in
`nupp.lua` sets the default, and the language server reads the same setting.

## `any`, and the escape hatches

`any` is compatible with everything in both directions. Reading a field of
`any` gives `any`; calling it gives `any` with no arity or argument checks. It
also swallows unions — `any | string` is `any`.

There is no `unknown` and no `never`, and no bottom type of any kind.
Subtracting every member of a union leaves the union alone rather than
producing an empty type.

`as` is an assertion the checker trusts completely, in both directions:

```nupp
local n = ("5" as any) as number   -- checks clean
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

- [Primitive types](primitives.md) — the builtin names, unions, optionals,
  collections, and aliases.
- [Records and structs](records.md) — nominal tables and FFI cdata.
- [Interfaces](interfaces.md) — structural satisfaction, `is`, and metamethods.
- [Property capabilities](properties.md) — independent read and write views.
- [Unions](unions.md) — literal sets, tagged unions, and exhaustiveness.
- [Intersections](intersections.md) — capability composition, overloads, and
  overloaded constructors.
- [Generics](generics.md) — type parameters, inference, and bounds.
- [Type packs](packs.md) — heterogeneous variadics, Lua value-list adjustment,
  protected calls, and coroutine protocols.
- [Narrowing](narrowing.md) — what proves what, and what does not.

For where a declaration lives and how modules see it, read
[declarations and modules](../modules.md).
