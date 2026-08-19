# Performance

What Nupp does to make a program fast, with the Lua it actually generates for
each rewrite.

LuaJIT's trace compiler does the hot-path work, so everything here is either
something the checker knows that LuaJIT cannot, or a shape chosen so a trace
forms at all. A pass lands only with a LuaJIT-enabled benchmark and a static
proof that it preserves behavior. Nothing is a promise about timing: thresholds
are measured implementation details, and every rewrite preserves answers. The
design catalog is
[`plans/014-optimizations.md`](../../plans/014-optimizations.md).

```bash
nupp build -O1
nupp run -O1 --remarks app.nupp
```

Two groups follow. **Always-on lowerings** need no flag and are part of what the
language means. **Optimization passes** are the `-O1` catalog.

Every generated tab below is the compiler's real output with whitespace
normalized and the module prelude elided. Temporary names are stable but not a
promise.

## Always-on lowerings

### Typed call projection

`{name} = path` fills a parameter from the field of `path` that the parameter
names, and `{a, b} = path` fills several from one operand. Because the operand
is confined to a name or dotted path, the reads are unordered and the shared
prefix is bound once. There is no argument table, reflection, varargs pack,
runtime arity choice, generated function, closure, or upvalue.

::: code-group
```nupp [Nupp]
local record Vec2
    x: number
    y: number
end

local record Velocity
    dx: number
    dy: number
end

local record Body
    position: Vec2
    velocity: Velocity
end

function m.step(entity: Entity, delta: number): nil
    update(delta, {x, y} = entity.body.position, {dx, dy} = entity.body.velocity)
end
```

```lua [Generated Lua]
function m.step(entity, delta)
    const __nuppT1 = delta
    const __nuppT2 = entity.body
    const __nuppT3 = __nuppT2.position
    const __nuppT4 = __nuppT2.velocity
    update(__nuppT1, __nuppT3.x, __nuppT3.y, __nuppT4.dx, __nuppT4.dy)
end
```
:::

`entity.body` is read once and shared by both operands. A plucked name is read
as that field of the operand, so the operand must actually have a field of that
name, so `(dx, dy)` requires a `dx` and a `dy`.

Only reusable path nodes receive locals; one-use leaves stay in the call. Safe
calls keep the same flat signature, using staged nil guards in statement
position and early returns in returned position, so plucked paths are not
evaluated when the call is suppressed. Nested where Lua cannot host local
bindings, the projection repeats rather than allocate an immediately invoked
closure:

::: code-group
```nupp [Nupp]
local moved = enabled and update(delta, {x, y} = entity.body.position)
```

```lua [Generated Lua]
local moved = enabled and update(
    delta,
    entity.body.position.x,
    entity.body.position.y
)
```
:::

### Table intrinsics

`table.new` and `table.clear` lower to private module bindings, because LuaJIT
does not expose them until their builtin modules are loaded.

::: code-group
```nupp [Nupp]
function m.build(): {string:boolean}
    local cache = table.new(128, 8)
    cache.ready = true
    table.clear(cache)
    return cache
end
```

```lua [Generated Lua]
const __nuppNew = require("table.new")
const __nuppClear = require("table.clear")

function m.build()
    local cache = __nuppNew(128, 8)
    cache.ready = true
    __nuppClear(cache)
    return cache
end
```
:::

Each used builtin is bound once per generated module and omitted when unused;
`OPT-1` shares the `table.new` binding. Recognition follows the stable prelude
definition, so a shadowed `table` is untouched and generated modules stay
standalone under external LuaJIT.

::: tip See also
When the function is marked `@aot`, the same `table.new` identity lowers to
`lua_createtable`, and the writes that fill the fresh table become public
raw-set calls, so the whole construction is one native call; see [building
ordinary Lua values](aot.md#building-ordinary-lua-values). The allocation
itself costs the same either way, so `@aot` pays where a profile puts the time
in the construction loop, not wherever a table is allocated.
:::

### `string.buffer`

`string.buffer` is reachable through the builtin `string` namespace with no
source-level `require`.

::: code-group
```nupp [Nupp]
function m.pair(): string
    local b = string.buffer.new()
    b:put("a", "b")
    return b:tostring()
end
```

```lua [Generated Lua]
const __nuppBuffer = require("string.buffer")

function m.pair()
    local b = __nuppBuffer.new()
    b:put("a", "b")
    return b:tostring()
end
```
:::

LuaJIT keeps the module in `package.loaded` and puts nothing on the runtime
`string` table, so the whole expression lowers to a private binding rather than
modifying that table. Writing the `require` yourself still works, and `OPT-5`
shares the binding. A shadowed `string` is ordinary table access.

### Switch dispatch

A [switch expression](../switch-expressions.md) lowers to lexical
selector/result locals and an ordered `if`/`elseif` chain. It is never wrapped
in an immediately invoked function, so one in a hot loop adds no
function-construction bytecode that would abort and blacklist a trace. Type-case
bindings reuse the one selector local, so a computed selector is never repeated.

An arm whose result must be computed keeps those branches:

::: code-group
```nupp [Nupp]
local text = switch status do
    case 200 -> formatStatus(status)
    case 301 -> "redirect"
    else -> "other"
end
```

```lua [Generated Lua]
local __nuppT5 = status
local __nuppT6
if __nuppT5 == 200 then __nuppT6 = formatStatus(status)
elseif __nuppT5 == 301 then __nuppT6 = "redirect"
else __nuppT6 = "other"
end
local text = __nuppT6
```
:::

#### Static result maps

When every case and result, `else` included, is a compiler-known inert scalar,
and there are enough of them, the decision finishes in one table read instead.
Integer cases packed into a narrow span become a dense array indexed through an
offset:

::: code-group
```nupp [Nupp]
local label = switch byte do
    case 9 -> "tab"
    case 10 -> "newline"
    case 11 -> "vertical tab"
    case 12 -> "form feed"
    case 13 -> "return"
    else -> "other"
end
```

```lua [Generated Lua]
const __nuppSwitchMap1 = {"tab", "newline", "vertical tab", "form feed", "return"}

local __nuppT1 = byte
local __nuppT2
__nuppT2 = __nuppSwitchMap1[__nuppT1 - (9) + 1]
if __nuppT2 == nil then __nuppT2 = "other" end
local label = __nuppT2
```
:::

Integers spread over a wide span become a hash-keyed map instead of a dense
array with holes:

::: code-group
```nupp [Nupp]
local again = switch status do
    case 408 -> true
    case 409 -> true
    case 421 -> true
    case 423 -> true
    case 425 -> true
    case 426 -> true
    case 428 -> true
    case 429 -> true
    case 500 -> true
    case 501 -> true
    case 502 -> true
    case 503 -> true
    case 504 -> true
    case 505 -> true
    case 506 -> true
    case 507 -> true
    else -> false
end
```

```lua [Generated Lua]
const __nuppSwitchMap1 = {
    [408] = true, [409] = true, [421] = true, [423] = true,
    [425] = true, [426] = true, [428] = true, [429] = true,
    [500] = true, [501] = true, [502] = true, [503] = true,
    [504] = true, [505] = true, [506] = true, [507] = true,
}

local __nuppT1 = status
local __nuppT2
__nuppT2 = __nuppSwitchMap1[__nuppT1]
if __nuppT2 == nil then __nuppT2 = false end
local again = __nuppT2
```
:::

A missing key is already `nil`, so neither integer form needs a range guard and
holes need no placeholder. String cases use the same shape. An arm which itself
produces `nil` is the exceptional case: a private sentinel distinguishes that
hit from a miss, and the sentinel is omitted from every map without a nil
result.

::: code-group
```nupp [Nupp]
local kind = switch word do
    case "and" -> "operator"
    case "break" -> "statement"
    case "do" -> "block"
    case "else" -> nil
    case "end" -> "block"
    case "false" -> "literal"
    case "for" -> "loop"
    case "function" -> "declaration"
    else -> "name"
end
```

```lua [Generated Lua]
const __nuppSwitchNil2 = {}
const __nuppSwitchMap3 = {
    ["and"] = "operator", ["break"] = "statement", ["do"] = "block",
    ["else"] = __nuppSwitchNil2, ["end"] = "block", ["false"] = "literal",
    ["for"] = "loop", ["function"] = "declaration",
}

local __nuppT3 = word
local __nuppT4
__nuppT4 = __nuppSwitchMap3[__nuppT3]
if __nuppT4 == nil then __nuppT4 = "name"
elseif __nuppT4 == __nuppSwitchNil2 then __nuppT4 = nil end
local kind = __nuppT4
```
:::

Every map is allocated once in generated module setup, never at the switch site.

::: tip See also
The AOT scalar subset admits a switch as the sole initializer of one local and
emits a native C `switch` for an exact-width selector; see
[scalar switch initializers](aot.md#scalar-switch-initializers).
:::

#### Conditions that keep ordered branches

Ordered branches come back for coverage builds, which need one instrumentable
condition per authored case, and for small maps, block arms, destructuring,
contextual `yield`, early `return`, refinements, any result whose evaluation can
be observed, and a nested switch in an arm. Exact thresholds are measured
implementation details rather than language promises.

Record cases use nominal metatable identity. When checking proves the remaining
selector is entirely records, lowering reads `__index` without a safe-navigation
guard and may share that read across a leading run of record cases. An optional,
gradual, primitive, refined, or otherwise open selector keeps the guarded or
authored-order predicate.

#### Rejected and deferred plans

There is no per-dispatch C helper, function table, BDD, MTBDD, or LuaJIT VM
extension. Stock LuaJIT cannot jump from a computed case ordinal to an arbitrary
lexical arm, so a lookup is used only when it is the end of the decision rather
than the start of a second dispatch.

Perfect hashing was implemented and measured rather than assumed, and ships in
neither form. A string perfect hash lost outright to LuaJIT's own table, because
verifying a hit needs the original string comparison back. A collision-free
32-bit hash into a fixed-width array is a different case: at sixteen to
sixty-four sparse integer cases it is the largest compiled win measured anywhere
in this work, twelve to twenty-one times the ordered chain, and the largest
interpreted regression, 1.7 to 2.7 times worse. Backing it with a Lua array
instead of an FFI one halves the interpreted penalty and gives up most of the
compiled margin without removing the cliff. Choosing correctly needs a hotness
input the cost model does not have, so it is deferred rather than rejected;
`bench/switch-dispatch.lua` keeps both `ph-ffi` and `ph-lua` baselines, and
`plans/057-switch-dispatch-optimization.md` records the decision.

## Optimization passes

    nupp build -O1
    nupp run -O1 app.nupp

`-O0`, the default, rewrites nothing: its generated Lua is the language
semantics with types erased. `-O1` enables every current pass; `-O2` means the
same today and reserves room for a stronger tier later. The level is part of the
build key, so changing it triggers a cold build.

Each pass below is named by a stable `OPT-n` code.

| Code | Name | Level | Rewrite |
| --- | --- | --- | --- |
| `OPT-1` | `presize` | -O1 | Size an empty table for the writes about to follow |
| `OPT-2` | numeric-ipairs | -O1 | Use a numeric loop for a proved stable dense array |
| `OPT-3` | constant-fold | -O1 | Fold exact primitives, branches, dead loops, and immutable paths |
| `OPT-4` | static-callable | -O1 | Bind repeated immutable dotted callees at first use |
| `OPT-5` | concat-buffer | -O1 | Append to a string.buffer instead of rebuilding a string each pass |
| `OPT-6` | indexed-range | -O1 | Select proved direct access and scalar-replace indexed views |

### `OPT-1`, presizing

Consecutive named writes that reveal an empty table's contents move into the
constructor, which LuaJIT sizes directly with no `table.new` call.

::: code-group
```nupp [Nupp]
function m.make(): {string:integer}
    local point = {}
    point.x = 1
    point.y = 2
    point.z = 3
    return point
end
```

```lua [-O1]
function m.make()
    local point = {
        x = 1,
        y = 2,
        z = 3,
    }
    return point
end
```

```lua [-O0]
function m.make()
    local point = {}
    point.x = 1
    point.y = 2
    point.z = 3
    return point
end
```
:::

Computed keys, repeated fields, multiple assignment, or an unrelated statement
between writes retain the assignments and use `table.new` with the capacity the
scan discovered. The scan steps over unrelated statements but stops when the
table is read, escapes, is reassigned, or reaches a conditional write. Capacity
is not observable, so the win is avoided growth allocations and copying, not a
smaller surviving table.

### `OPT-2`, numeric `ipairs`

A dense literal supplies a static boundary. When effect and alias analysis also
prove the binding and shape cannot change, the loop becomes numeric.

::: code-group
```nupp [Nupp]
function m.total(): integer
    local xs: {integer} = {10, 20, 30}
    local sum: integer = 0
    for index, value in ipairs(xs) do
        sum = sum + index * value
    end
    return sum
end
```

```lua [-O1]
function m.total()
    local xs = {10, 20, 30}
    local sum = 0
    for index = 1, 3 do
        local value = xs[index]
        sum = sum + index * value
    end
    return sum
end
```

```lua [-O0]
function m.total()
    local xs = {10, 20, 30}
    local sum = 0
    for index, value in ipairs(xs) do
        sum = sum + index * value
    end
    return sum
end
```
:::

An array type alone is insufficient. A shape-changing write through any alias,
an unknown call, yield, metatable effect, or shadowed `ipairs` keeps the generic
loop, including an ordinary call to a function parameter, whose effects cannot
be resolved. See [effect summaries](../effects.md). The static bound is
intentional; a dynamic raw length was flat or slower after tracing.

### `OPT-3`, constant folding

Exact integer arithmetic, strings, comparisons, and boolean selection fold, and
primitive `const` values propagate through later expressions.

::: code-group
```nupp [Nupp]
const prefix = "nu"
const answer = (2 + 3) * 4

function m.show(): nil
    print((true and prefix) .. "pp", answer, "nupp" < "rust")
end
```

```lua [-O1]
const prefix = "nu"
const answer = 20

function m.show()
    print("nupp", 20, true)
end
```

```lua [-O0]
const prefix = "nu"
const answer = (2 + 3) * 4

function m.show()
    print((true and prefix) .. "pp", answer, "nupp" < "rust")
end
```
:::

Floating-point arithmetic, cdata, calls, allocation, and mutable bindings stay
at runtime so LuaJIT retains their rounding, identity, errors, and lifetimes.

#### Integer division and the bit operators

`//` folds as the expression it lowers to, `math.floor((a) / (b))`, rather than
as an integer division that would disagree with it about a quotient no double
holds exactly. Folding one usually collapses what surrounds it, which is what
makes aligning a constant up a single literal. `&`, `|`, `~`, `<<`, `>>` and
`~>>` fold through BitOp, which is their declared meaning rather than an
approximation of it: operands normalize to 32 bits and results come back signed,
so the folded answers are the surprising ones.

::: code-group
```nupp [Nupp]
const CACHE = 64
const RAW = 40
const STRIDE = (RAW + CACHE - 1) // CACHE * CACHE

const FLAGS = 1 << 3 | 1
const WRAP = 1 << 32   -- a shift count is taken modulo 32
const LOG = -8 >> 1    -- the plain shift is logical
const AR = -8 ~>> 1    -- the tilde shift is arithmetic

function m.show(): nil
    print(STRIDE, FLAGS, WRAP, LOG, AR)
end
```

```lua [-O1]
const CACHE = 64
const RAW = 40
const STRIDE = 64

const FLAGS = 9
const WRAP = 1
const LOG = 2147483644
const AR = -4

function m.show()
    print(64, 9, 1, 2147483644, -4)
end
```

```lua [-O0]
const CACHE = 64
const RAW = 40
const STRIDE = math.floor(((RAW + CACHE - 1)) / (CACHE)) * CACHE

const FLAGS = 1 << 3 | 1
const WRAP = 1 << 32
const LOG = -8 >> 1
const AR = -8 ~>> 1

function m.show()
    print(STRIDE, FLAGS, WRAP, LOG, AR)
end
```
:::

A zero divisor keeps the division: its answer is an infinity, not an integer.
Folding runs the same primitive the emitted operator would have, so the two
cannot disagree by construction; the test sweeps one against the other anyway.

#### Loops that cannot run

A loop whose constant bounds admit no first iteration is not emitted. The empty
`do` left behind compiles to nothing.

::: code-group
```nupp [Nupp]
function m.run(unreachable, alsoUnreachable): nil
    while false do
        unreachable()
    end
    for index = 1, 0 do
        alsoUnreachable(index)
    end
end
```

```lua [-O1]
function m.run(unreachable, alsoUnreachable)
    do
    end
    do
    end
end
```

```lua [-O0]
function m.run(unreachable, alsoUnreachable)
    while false do
        unreachable()
    end
    for index = 1, 0 do
        alsoUnreachable(index)
    end
end
```
:::

A step of zero is left alone: `for i = 1, 10, 0` does not terminate, and
removing it would remove the hang rather than the cost of it.

#### Constant branches

If every tested condition is constant, only the selected arm is emitted; a `do`
preserves the arm's original scope.

::: code-group
```nupp [Nupp]
function m.pick(): nil
    if false then
        error("unreachable")
    elseif 2 < 3 then
        print("reachable")
    else
        error("also unreachable")
    end
end
```

```lua [-O1]
function m.pick()
    do
        print("reachable")
    end
end
```

```lua [-O0]
function m.pick()
    if false then
        error("unreachable")
    elseif 2 < 3 then
        print("reachable")
    else
        error("also unreachable")
    end
end
```
:::

#### Nested immutable paths

`const M = {}` fixes the module-table binding, not the table. `const M.field`
fixes one named slot, leaving ordinary fields mutable; `const... M.field` is the
auto-deep form for every named field in a fresh table graph. A read whose every
edge is immutable becomes its value.

::: code-group
```nupp [Nupp]
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

function m.show(): nil
    print(Settings.mixed.NAME, Settings.mixed.count, Settings.deep.nested.VERSION)
end
```

```lua [-O1]
-- app.lua
const Settings = require("settings")

function m.show()
    print("nupp", Settings.mixed.count, 1)
end
```

```lua [-O0]
-- app.lua
const Settings = require("settings")

function m.show()
    print(Settings.mixed.NAME, Settings.mixed.count, Settings.deep.nested.VERSION)
end
```
:::

`mixed.count` is an ordinary mutable field, so it survives. One mutable parent
anywhere on the path keeps the whole read intact. `require` is never removed or
moved, because loading a module may have effects. No `module` keyword or runtime
freezing is involved: `const` records the checked, shallow guarantee and
`const...` applies it recursively to fresh named fields. See
[comptime types](../type-system/type-level-computation.md) for the binder.

### `OPT-4`, static callable binding

Repeated statement-position calls through one immutable path share a local
bound at the first call.

::: code-group
```nupp [Nupp]
-- service.nupp
const S = {}
const... S.x = {
    y = function(): nil
        print("call")
    end,
}
return S

-- app.nupp
const service = require("service")

function m.show(): nil
    service.x.y()
    service.x.y()
end
```

```lua [-O1]
-- app.lua
const service = require("service")

function m.show()
    const __nupp_call_1 = service.x.y
    __nupp_call_1()
    __nupp_call_1()
end
```

```lua [-O0]
-- app.lua
const service = require("service")

function m.show()
    service.x.y()
    service.x.y()
end
```
:::

The root and every field must be `const`, which is why `service.nupp` above
declares the callee with `const...` rather than an ordinary `function S.x.y()`,
whose `y` slot would stay mutable and decline the rewrite. One call is left
alone. First-use binding preserves lookup order and the error line, and reuse
stays within one lexical block. Labels, `goto`, and calls with specialized FFI,
ownership, construction, or output-parameter lowering are not rewritten.

### `OPT-5`, concat buffer

A string appended to round a loop is built in a `string.buffer` and read back
once, instead of being rebuilt on every pass.

::: code-group
```nupp [Nupp]
function m.join(items: {string}): string
    local out = ""
    for _, item in ipairs(items) do
        out = out .. item .. ","
    end
    return out
end
```

```lua [-O1]
const __nuppBuffer = require("string.buffer")

function m.join(items)
    local out = ""
    local __nuppBuf_1 = __nuppBuffer.new()
    for _, item in ipairs(items) do
        __nuppBuf_1:put(item, ",")
    end
    out = __nuppBuf_1:tostring()
    return out
end
```

```lua [-O0]
function m.join(items)
    local out = ""
    for _, item in ipairs(items) do
        out = out .. item .. ","
    end
    return out
end
```
:::

`out = out .. piece` is O(n²), because every pass allocates and interns a string
holding everything so far, so this is the one win here the trace compiler could
not have folded itself. `bench/concat.lua` measures 1.8x over eight pieces
rising to 3.6x over sixty-four, still climbing.

The accumulator keeps its declaration and is assigned back where the loop
closes, so everything after it reads an ordinary string. The rewrite requires
the initializer to be `""`, every mention inside the loop to be the one
`out = out .. ...`, and nothing to touch the binding between declaration and
loop. A read of the half-built string, a capture by a function written in the
loop, a prepend (`out = item .. out`), or a second accumulation keeps the
concatenation, as does a `..` the checker did not prove primitive: an `any`
operand may carry a `__concat`, which `put` would not run.

Straight-line concatenation is untouched. Lua concatenates multiple operands in
one operation, and a buffer costs about what two concatenations cost.

### `OPT-6`, indexed views

[`indexed.range`](../spans.md#one-range-for-several-spans) checks one inclusive
range against every participating trusted Span or SoA view. The successful check
proves matching indexed reads and writes non-raising inside the dominated
numeric loop, and that proof is part of checking at every level, which is what
permits those calls inside `noraise` code. At `-O1` the backend also spends the
proof, replacing each checked access with direct FFI element access:

::: code-group
```nupp [Nupp]
function m.dot(leftView: span.Span<Value>, rightView: span.Span<Value>): integer
    const left = leftView
    const right = rightView
    const indexes = indexed.range(1, #left, left, right)
    local total: integer = 0
    for index = indexes.first, indexes.last do
        total = total + left[index].n * right[index].n
    end
    return total
end
```

```lua [-O1]
function m.dot(leftView, rightView)
    const left = leftView.count
    const right = rightView.count
    const indexes = __nuppModule._rangeCounts(1, left, left, right)
    local total = 0
    for index = indexes.first, indexes.last do
        total = total
            + leftView.pointer[leftView.offset + index - 1].n
            * rightView.pointer[rightView.offset + index - 1].n
    end
    return total
end
```

```lua [-O0]
function m.dot(leftView, rightView)
    const left = leftView
    const right = rightView
    const indexes = indexed.range(1, left.count, left, right)
    local total = 0
    for index = indexes.first, indexes.last do
        total = total + left:get(index).n * right:get(index).n
    end
    return total
end
```
:::

Every view handed to `indexed.range` must be a `const` name, which is why the
parameters are rebound above. The range call still validates every span once,
and the generated access still includes the span's physical offset. `-O0`, held
frames, a computed index, a different span, or an access outside the witnessed
loop retains one checked helper operation. The proof is local to the function
containing `indexed.range`; passing its bounds or result elsewhere does not
transport it.

The same pass scalar-replaces the view itself. Above, `left` and `right` become
bare counts rather than span objects. The checked finish, root, offset, count,
and access capability are kept as compiler facts instead of allocating a
wrapper.

#### SoA columns

A [SoA](../soa.md) view is the other admitted shape. The canonical
`for index = 1, #rows` loop proves every row access in bounds, and a const-bound
view lets each field become a direct typed-column load or store:

::: code-group
```nupp [Nupp]
function m.advance(view: soa.WriteSpan<Particle>, delta: float): nil
    const rows = view
    for index = 1, #rows do
        rows[index].x += rows[index].dx * delta
        rows[index].y += rows[index].dy * delta
    end
end
```

```lua [-O1]
function m.advance(view, delta)
    const rows = view.count
    for index = 1, rows do
        view.columns[1][view.offset + index - 1] +=
            view.columns[3][view.offset + index - 1] * delta
        view.columns[2][view.offset + index - 1] +=
            view.columns[4][view.offset + index - 1] * delta
    end
end
```

```lua [-O0]
function m.advance(view, delta)
    const rows = view
    for index = 1, rows.count do
        rows.columns[1][rows:checkedIndex(index)] +=
            rows.columns[3][rows:checkedIndex(index)] * delta
        rows.columns[2][rows:checkedIndex(index)] +=
            rows.columns[4][rows:checkedIndex(index)] * delta
    end
end
```
:::

`--remarks` reports both halves of that:

    OPT-6: indexed-range: lowers 4 soa accesses
    OPT-6: view-scalar-replacement: virtualizes one alias

#### Admitted roots

An arbitrary index keeps its runtime bounds check. Admitted roots come from
`span.fromString`, the shared and writable C-array constructors,
`heap.Array:read()`/`write()`, and `soa.Array:read()`/`write()`. Slices retain
one checked finish scalar, shared downgrades their count, resolved SoA field
projections select the column directly, and nested combinations compose offsets
without wrapper tables. Dynamic base, offset, count, and column expressions are
captured once in source order, and constructor validation, exclusive
acquisition, dirty marking, and other producer effects still execute once.
Access stays rooted through the source owner, so scalar replacement cannot
detach a pointer or column from its anchor.

Directly called, nonrecursive local functions in the same module may transport
an admitted view through parameters or one return value as flattened runtime
state. Recursive, exported, dynamic, foreign, cross-module, `any`, and otherwise
opaque boundaries retain the materialized ABI, as does returning, capturing, or
storing the view.

::: tip See also
An `@aot` function retains the same resolved field identities and
single-map-loop fact, and its backend keeps unit strides in IR for direct scalar
or lane lowering; see [automatic vectorization](aot.md#automatic-vectorization).
:::

### Rewrites deliberately not made

Nupp does not cache a closure created inside a loop: that changes function
identity. The `loop-invariant-closure` lint instead suggests lifting a closure
that does not depend on the iteration.

```nupp
local isClick = |event| -> event.kind == "click"
for _, item in ipairs(items) do
    register(item, isClick)
end
```

Suppress an intentional case with `@allow("loop-invariant-closure")`; see
[lints](../lints.md). A closure that does depend on the iteration cannot be
lifted, and costs the loop its trace all the same; `jit-loop-closure` says so
where a project asks for it, and anyway inside a function annotated `@jit`.

Two benchmarks argued against passes that were therefore never written.
`bench/ffi-hoisting.lua` finds that caching a ctype is the interpreter's win
alone, though the clib symbol binding it also measures is real and already
emitted. `bench/scratch-reuse.lua` finds that hoisting a loop-local table or
`ffi.new` out of its loop is slower than letting allocation sinking handle it.
Both exit non-zero if their finding stops holding.

## Benchmark details

Fresh local medians with LuaJIT enabled, measuring the generated-Lua shapes each
pass produces rather than checker time.

| Pass and scenario | Before | After | Change |
| --- | --- | --- | --- |
| OPT-1, 200,000 tables, four named fields | 0.0159s | 0.0053s | 3.02x faster |
| OPT-1, 200,000 tables, eight hash fields | 0.0262s | 0.0106s | 2.47x faster |
| OPT-1, 200,000 tables, four array slots | 0.0168s | 0.0024s | 7.06x faster |
| OPT-2, eight million visits, 4-element arrays | 0.0126s | 0.0087s | 1.44x faster |
| OPT-2, eight million visits, 32-element arrays | 0.0053s | 0.0050s | 1.06x faster |
| OPT-2, eight million visits, 256-element arrays | 0.0051s | 0.0047s | 1.07x faster |
| OPT-3, 20,000 primitive expressions, load and run | 0.0039s | 0.0024s | 1.64x faster |
| OPT-3, 20,000 nested paths, load only | 0.0095s | 0.0025s | 3.82x faster |
| OPT-3, 20,000 nested paths, load and run | 0.0099s | 0.0025s | 3.95x faster |
| OPT-4, 20,000 dotted calls, load only | 0.0027s | 0.0011s | 2.54x faster |
| OPT-4, 20,000 dotted calls, load and run | 0.0030s | 0.0012s | 2.53x faster |
| OPT-6, 8 million struct element updates | 0.01075s | 0.00735s | 1.46x faster |
| OPT-6, SoA projected update vs handwritten columns | 0.00296s | 0.00307s | 1.037x of direct |
| OPT-6, 500,000 slice constructions | 0.12183s | 0.00425s | 28.7x faster |

Primitive folding reduced its generated input by 32.1%, nested propagation by
60.8%, static callable binding by 63.6%; warmed results were 0.99x, 2.01x, and
1.06x. Hot results are workload- and trace-dependent, so the reliable constant
and callable wins are smaller source and cold startup.

    luajit bench/presize.lua
    luajit bench/numeric-ipairs.lua
    luajit bench/constant-folding.lua
    luajit bench/constant-propagation.lua
    luajit bench/static-callable.lua
    bench/span-range-lowering/run.sh

Three more decide whether a pass is worth writing at all:

    luajit bench/ffi-hoisting.lua
    luajit bench/concat.lua
    luajit bench/scratch-reuse.lua

`concat` argued for `OPT-5` and now guards it. The others argued against passes
that are therefore not here: caching a ctype is the interpreter's win alone,
though the clib symbol binding `ffi-hoisting` also measures is real and already
emitted, and hoisting a loop-local table or `ffi.new` out of its loop is slower
than letting allocation sinking handle it. All three exit non-zero if their
finding stops holding.

The `OPT-6` rows compare the pass disabled against enabled on an arm64 Apple
host after warmup, where the optimized trace matched handwritten direct FFI in
counted IR shape and timing. The benchmark adapts the position/velocity kernel,
the repository having no production hot loop written with a same-function
witness. The slice figures are evidence for narrow derived-view scalar
replacement, not general table escape analysis. The committed
[`span-range-lowering` results](../../bench/span-range-lowering/README.md) have
the full Span, heap, SoA, dirty-acquisition, and trace matrix, and
`bench/span-range-lowering/trace.sh` prints the opcode-category comparison.

## Inspecting, controlling, and measuring

    nupp build -O1 --remarks
    nupp build -O1 -Zno-opt=OPT-2

`--remarks` reports both successful rewrites and declined proofs, including the
source location that stopped an analysis. Remarks never fail a build; they come
from `build` and `run`, and `check` does not optimize. `-Zno-opt=CODE` disables
one pass for miscompile bisection, where the codes are stable and the `-Z`
spelling is an unstable debugging interface, and `-O0` disables every rewrite.

Measure before deciding any of this matters:

- [Profiling](profiling.md) says where the time actually goes.
- [LuaJIT trace checking](jit-trace-checking.md) and `nupp bc --check FILE` find
  recorder blockers in the exact generated bytecode, without a quiet machine and
  without executing anything.
- `bench/` holds the LuaJIT-enabled benchmark behind every pass.

## Observable behavior

Passes preserve answers. One that trades a non-answer guarantee for speed must
explicitly check a named `--relax` or `@relax` permission; `OPT-6` requires
`frames`. The compiler fixpoint verifies that compiling the compiler at `-O1`
produces output byte-identical to compiling it at `-O0` while its guarantees are
held.

## Next

- [LuaJIT trace checking](jit-trace-checking.md): recorder blockers in source,
  bytecode, or an observed run.
- [Ahead-of-time compilation](aot.md): the native scalar subset and its
  boundaries.
