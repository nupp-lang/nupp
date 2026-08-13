# Constant folding

`OPT-3` evaluates what it can at compile time and propagates the result, so a
value a reader can work out is not one the program works out again on every
run:

```nupp:playground
local m = {}

const WIDTH: integer = 8

function m.area(): integer
    return WIDTH * 4
end

return m
```

`m.area` lowers to `return 32`. What follows is each rewrite the pass makes,
and the condition under which it declines.

## Exact primitives and local propagation

Nupp folds exact integer arithmetic, strings, comparisons, and boolean
selection. Primitive `const` values propagate through later expressions.

::: code-group
```nupp [Original Nupp]
const prefix = "nu"
const answer = (2 + 3) * 4
print((true and prefix) .. "pp", answer, "nupp" < "rust")
```

```lua [Optimized Lua]
const prefix = "nu"
const answer = 20
print("nupp", 20, true)
```

```lua [Unoptimized Lua]
const prefix = "nu"
const answer = (2 + 3) * 4
print((false or prefix) .. "pp", answer, "nupp" < "rust")
```
:::

Floating-point arithmetic, cdata, calls, allocation, and mutable bindings stay
at runtime so LuaJIT retains their rounding, identity, errors, and lifetimes.

## Integer division and the bit operators

`//` folds as the expression it lowers to, `math.floor((a) / (b))`, rather than
as an integer division that would disagree with it about a quotient no double
holds exactly. Folding one usually collapses what surrounds it, which is what
makes aligning a constant up a single literal:

::: code-group
```nupp [Original Nupp]
const CACHE = 64
const RAW = 40
const STRIDE = (RAW + CACHE - 1) // CACHE * CACHE
```

```lua [Optimized Lua]
const CACHE = 64
const RAW = 40
const STRIDE = 64
```

```lua [Unoptimized Lua]
const CACHE = 64
const RAW = 40
const STRIDE = math.floor((103) / (64)) * 64
```
:::

A zero divisor keeps the division, since its answer is an infinity rather than
an integer.

`&`, `|`, `~`, `<<`, `>>` and `~>>` fold through BitOp, which is their declared
meaning rather than an approximation of it: operands normalize to 32 bits and
results come back signed. The folded answers are therefore the surprising ones.

```nupp
const FLAGS = 1 << 3 | 1 -- 9
const WRAP = 1 << 32 -- 1, a shift count being taken modulo 32
const LOG = -8 >> 1 -- 2147483644, the plain shift being logical
const AR = -8 ~>> 1 -- -4, the tilde shift being arithmetic
```

Folding runs the same primitive the emitted operator would have, so the two
cannot disagree by construction. The test sweeps one against the other over a
range of operands regardless, that being cheaper than trusting the argument.

## Loops that cannot run

A loop whose constant bounds admit no first iteration is not emitted. An empty
`do` holds its opening and closing lines, and LuaJIT compiles that to nothing.

::: code-group
```nupp [Original Nupp]
while false do
    unreachable()
end
for index = 1, 0 do
    alsoUnreachable(index)
end
```

```lua [Optimized Lua]
do
end
do
end
```

```lua [Unoptimized Lua]
while false do
    unreachable()
end
for index = 1, 0 do
    alsoUnreachable(index)
end
```
:::

A step of zero is left alone. `for i = 1, 10, 0` does not terminate, and
removing it would be removing the hang rather than the cost of it.

## Constant branches

If every tested condition is constant, only the selected arm is emitted. A
`do` preserves the arm's original scope.

::: code-group
```nupp [Original Nupp]
if false then
    error("unreachable")
elseif 2 < 3 then
    print("reachable")
else
    error("also unreachable")
end
```

```lua [Optimized Lua]
do
    print("reachable")
end
```

```lua [Unoptimized Lua]
if false then
    error("unreachable")
elseif 2 < 3 then
    print("reachable")
else
    error("also unreachable")
end
```
:::

## Nested immutable paths

`const M = {}` fixes the module-table binding, not the table. `const M.field`
fixes one named slot; ordinary fields remain mutable. `const... M.field` is the
auto-deep form for every named field in a fresh table graph.

::: code-group
```nupp [Original Nupp]
-- settings.nupp
const M = {}
const M.mixed = {
    const NAME = "nupp",
    count = 0,
}
const... M.deep = {
    nested = {VERSION = 1},
}
return M

-- app.nupp
const Settings = require("settings")
print(Settings.mixed.NAME, Settings.mixed.count,
    Settings.deep.nested.VERSION)
```

```lua [Optimized Lua]
-- settings.lua
const M = {}
M.mixed = {NAME = "nupp", count = 0}
M.deep = {nested = {VERSION = 1}}
return M

-- app.lua
const Settings = require("settings")
print("nupp", Settings.mixed.count, 1)
```

```lua [Unoptimized Lua]
-- settings.lua
const M = {}
M.mixed = {NAME = "nupp", count = 0}
M.deep = {nested = {VERSION = 1}}
return M

-- app.lua
const Settings = require("settings")
print(Settings.mixed.NAME, Settings.mixed.count,
    Settings.deep.nested.VERSION)
```
:::

Every edge from the `const` required-module binding to the leaf must be
immutable. One mutable parent keeps the read intact. `require` itself is never
removed or moved because loading a module may have effects. No `module` keyword
or runtime freezing is involved: `const` records the checked, shallow guarantee;
`const...` applies it recursively to fresh named fields.

## Next

- [Optimization](optimization.md): the other passes, and how to inspect or
  turn one off.
- [Comptime types](../type-system/type-level-computation.md): the
  `const` binder this pass reads.
