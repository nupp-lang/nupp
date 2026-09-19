---
order: 600
---

# Performance

Nupp uses type and effect information to simplify generated Lua:

::: code-group
```nupp [Nupp]
local point = {}
point.x = 1
point.y = 2
```

```lua [Generated Lua, -O1]
local point = {x = 1, y = 2}
```
:::

**Always-on lowerings** implement language features. **Optimization passes**
require `-O1`:

```bash
nupp build -O1
nupp run -O1 --remarks app.nupp
```

Generated examples normalize whitespace and omit the module prelude. Temporary
names may change.

## Always-on lowerings

### Typed call projection

`{a, b} = path` passes fields as positional arguments. Shared paths are read
once, without argument tables or closures.

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

Both operands share the `entity.body` read. See [named and plucked
arguments](../language/named-arguments.md) for syntax and field requirements.

Safe calls and short-circuit expressions evaluate plucked paths only when the
call runs:

::: code-group
```nupp [Nupp]
local moved = enabled and update(delta, {x, y} = entity.body.position)
```

```lua [Generated Lua]
local __nuppT3 = enabled
if __nuppT3 then
    const __nuppT7 = update
    const __nuppT4 = delta
    const __nuppT5 = entity.body
    const __nuppT6 = __nuppT5.position
    __nuppT3 = __nuppT7(__nuppT4, __nuppT6.x, __nuppT6.y)
end
local moved = __nuppT3
```
:::

### Table intrinsics

`table.new` and `table.clear` get private module bindings so their LuaJIT
builtins are available:

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

Under `@aot`, table construction and initialization can run in one native call.
See [building ordinary Lua values](ahead-of-time/lua-values.md).

### `string.buffer`

`string.buffer` needs no source-level `require`:

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

The private binding leaves the runtime `string` table untouched. An explicit
`require` also works; a shadowed `string` remains ordinary table access.

### Switch dispatch

A [switch](../language/switch-expressions.md) writes directly to its destination
when scope permits, without a closure. Computed selectors are saved once; these
examples use local scalar selectors.

Computed results keep an `if`/`elseif` chain:

::: code-group
```nupp [Nupp]
local text = switch status do
    case 200 -> formatStatus(status)
    case 301 -> "redirect"
    else -> "other"
end
```

```lua [Generated Lua]
local text
if status == 200 then text = formatStatus(status)
elseif status == 301 then text = "redirect"
else text = "other"
end
```
:::

#### Static result maps

Enough static scalar cases and results, including `else`, become one table read.
Closely spaced integers use an offset into a dense array:

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

local label = __nuppSwitchMap1[byte - (9) + 1]
if label == nil then label = "other" end
```
:::

Widely spaced integers use a hash-keyed map:

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

local again = __nuppSwitchMap1[status]
if again == nil then again = false end
```
:::

String cases use the same lookup, including cases that return `nil`:

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

local kind = __nuppSwitchMap3[word]
if kind == nil then kind = "name"
elseif kind == __nuppSwitchNil2 then kind = nil end
```
:::

Maps are allocated once per module.

AOT can emit a native C `switch` for exact-width selectors. See [scalar switches
and do
blocks](ahead-of-time/numeric-semantics.md#scalar-switch-expressions-and-do-blocks).

## Optimization passes

```bash
nupp build -O1
nupp run -O1 app.nupp
```

`-O0`, the default, disables optimization passes. `-O1` enables all current
passes; `-O2` is equivalent today. Changing levels triggers a cold build.

Each pass has a stable `OPT-n` code:

| Code | Name | Level | Rewrite |
| --- | --- | --- | --- |
| `OPT-1` | `presize` | -O1 | Size an empty table for the writes about to follow |
| `OPT-2` | numeric-ipairs | -O1 | Use a numeric loop for a proved stable dense array |
| `OPT-3` | constant-fold | -O1 | Fold exact primitives, branches, dead loops, and immutable paths |
| `OPT-4` | static-callable | -O1 | Bind repeated immutable dotted callees at first use |
| `OPT-5` | concat-buffer | -O1 | Append to a string.buffer instead of rebuilding a string each pass |
| `OPT-6` | indexed-range | -O1 | Remove repeated bounds checks and temporary view objects |
| `OPT-7` | inline-return-helper | -O1 | Inline a module's own single-return local helpers where they are called |
| `OPT-8` | const-monomorphize | -O1 | Specialize functions for known constant arguments |

### `OPT-1`, presizing

Consecutive named writes into an empty table become a constructor, which LuaJIT
sizes directly:

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

Other write patterns use `table.new` to reserve capacity and avoid growth and
copying. Reads, reassignment, conditional writes, or passing the table elsewhere
limit how much capacity can be reserved in advance.

### `OPT-2`, numeric `ipairs`

A loop over a dense literal becomes numeric when the compiler can prove the
array and its length stay fixed:

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

### `OPT-3`, constant folding

Exact integer arithmetic, strings, comparisons, boolean selection, and primitive
`const` values fold:

::: code-group
```nupp [Nupp]
const prefix = "nu"
const answer = (2 + 3) * 4

function m.show(): nil
    print((true and prefix) .. "pp", answer, "nupp" < "zulu")
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
    print((true and prefix) .. "pp", answer, "nupp" < "zulu")
end
```
:::

#### Unchanged locals

Ordinary scalar locals also propagate when their bindings are never reassigned:

::: code-group
```nupp [Nupp]
function m.answer(): number
    local size = 6
    return size * 7
end
```

```lua [-O1]
function m.answer()
    return 42
end
```

```lua [-O0]
function m.answer()
    local size = 6
    return size * 7
end
```
:::

Unused inert scalar declarations disappear after folding.

#### Short-circuit expressions

A known left operand simplifies `and`, `or`, and `??`. Selected calls run once
and produce one value; unselected operands do no work. Unknown left operands
still run.

::: code-group
```nupp [Nupp]
function m.choose(read: function(): boolean): (boolean, boolean, boolean)
    return false and read(), true or read(), true and read()
end
```

```lua [-O1]
function m.choose(read)
    return false, true, (read())
end
```

```lua [-O0]
function m.choose(read)
    return false and read(), true or read(), true and read()
end
```
:::

#### Integer division and the bit operators

`//` folds using `math.floor((a) / (b))`. Bit operators use BitOp semantics:
operands normalize to 32 bits and results are signed.

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

Division by zero stays at runtime.

#### Dead loops

Loops with no possible first iteration disappear. The remaining empty `do`
compiles to nothing:

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

A zero step remains unchanged because the loop does not terminate.

#### Constant branches

False arms disappear; a true arm becomes the final fallback. Remaining
conditions preserve evaluation order, and `do` preserves scope:

::: code-group
```nupp [Nupp]
function m.pick(active: boolean): nil
    if false then
        error("unreachable")
    elseif active then
        print("active")
    elseif 2 < 3 then
        print("reachable")
    else
        error("also unreachable")
    end
end
```

```lua [-O1]
function m.pick(active)
    do
        if active then
            print("active")
        else
            print("reachable")
        end
    end
end
```

```lua [-O0]
function m.pick(active)
    if false then
        error("unreachable")
    elseif active then
        print("active")
    elseif 2 < 3 then
        print("reachable")
    else
        error("also unreachable")
    end
end
```
:::

#### Nested immutable paths

`const M` fixes the binding, `const M.field` fixes one field, and `const...
M.field` recursively fixes fresh named fields. Reads through fully immutable
paths fold:

::: code-group
```nupp [Nupp]
-- settings.nupp
module settings

export const mixed = {
    const NAME = "nupp",
    count = 0,
}
export const deep = {
    const nested = {const VERSION = 1},
}

-- app.nupp
module app

const Settings = require("settings")

export function show(): nil
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

A mutable field or parent keeps the read intact. `require` stays in place
because [module loading](../language/modules.md) may have effects. These are
checked guarantees, not runtime freezing; see [const
binders](../language/types/comptime-types.md).

### `OPT-4`, static callable binding

Repeated statement-position calls through an immutable path share a local bound
at first use:

::: code-group
```nupp [Nupp]
-- service.nupp
module service

export const x = {
    const y = function(): nil
        print("call")
    end,
}

-- app.nupp
module app

const service = require("service")

export function show(): nil
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

The root and every field must be `const`. Calls share the binding within the
same block.

::: deepdive Call binding limits
The binding is created at first use to preserve lookup order and error
locations. Labels and `goto` prevent reuse, as do calls with special handling
for FFI, ownership, constructors, or output parameters. A single call needs no
shared binding.
:::

### `OPT-5`, concat buffer

A loop that appends to a string can use a `nupp.text` buffer:

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
const __nuppBuffer = require("nupp.text")

function m.join(items)
    local __nuppBuf_1 = __nuppBuffer.newBuffer()
    for _, item in ipairs(items) do
        __nuppBuf_1:put(item, ",")
    end
    return __nuppBuf_1:tostring()
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

Repeated concatenation copies the growing string and costs O(n²).

### `OPT-6`, indexed views

[](nupp.mem.indexed.range) validates an inclusive range for trusted Span or SoA
views. Matching accesses in the numeric loop become non-raising at every level,
including in `noraise` code. At `-O1`, they also become direct FFI accesses:

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

Views must be bound to `const` names. Validation runs once and physical offsets
are preserved.

#### SoA columns

For a const-bound [SoA view](../runtime/data/structure-of-arrays.md), `for index
= 1, #rows` proves row accesses in bounds and enables direct column loads and
stores:

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
    const columns = view.columns
    const base = view.offset - 1
    const xs = columns[1]
    const ys = columns[2]
    const dxs = columns[3]
    const dys = columns[4]
    for index = 1, rows do
        const physical = base + index
        xs[physical] += dxs[physical] * delta
        ys[physical] += dys[physical] * delta
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

::: note
`--remarks` reports both rewrites:

```text
OPT-6: indexed-range: lowers 4 soa accesses
OPT-6: view-scalar-replacement: virtualizes one alias
```

Column pointers and the physical base are bound once; each iteration computes
one physical index. The source owner stays live. These bindings primarily help
interpreted execution; LuaJIT can discover the same invariants.
:::

<a id="admitted-roots"></a>

#### Supported views

Supported views come from `span.fromString`, shared and writable C arrays,
`heap.Array:read()`/`write()`, and `soa.Array:read()`/`write()`. Slices and SoA
field projections are supported too. Arbitrary indices keep bounds checks.

See [SIMD lowering](ahead-of-time/vectorization.md) for AOT vectorization.

::: deepdive Removing view allocations
The pass can remove temporary view objects: `left` and `right` in the earlier
example become counts, while accesses use the original views. Slices, shared
downgrades, and SoA field projections combine their offsets without creating
wrapper objects. The source owner stays alive for the accesses.

Direct, nonrecursive local calls may pass or return views as flattened state.
Recursive, exported, dynamic, foreign, cross-module, and `any` boundaries keep
view objects, as do other returns, captures, and stores.
:::

### `OPT-7`, single-return helpers

A local helper with one return expression can be inlined at its call sites:

::: code-group
```nupp [Nupp]
local function rotateRight(value: int32, right: int32, left: int32): int32
    return (value >> right) | (value << left)
end

function m.spun(word: int32): int32
    return rotateRight(word, 7, 25)
end
```

```lua [Generated]
local function rotateRight(value, right, left)
   return (value >> right) | (value << left)
end

function m.spun(word)
   return ((word >> 7) | (word << 25))
end
```
:::

The declaration remains for other callers.

Inlining also lets constants and branches simplify:

::: code-group
```nupp [Nupp]
local function add(left: number, right: number): number
    return left + right
end

function m.answer(): number
    local size = add(2, 3)
    return size * 4
end
```

```lua [-O1]
local function add(left, right)
    return left + right
end

function m.answer()
    return 20
end
```

```lua [-O0]
local function add(left, right)
    return left + right
end

function m.answer()
    local size = add(2, 3)
    return size * 4
end
```
:::

[AOT](ahead-of-time/index.md) applies the same helper eligibility rules.

::: deepdive Inlining limits
Inlining requires:

- A nonrecursive, nongeneric local helper with one return expression.
- Stable bindings: no reassignment, duplicate module declarations, or shadowed free names.
- Exactly one argument per parameter, using names, literals, or non-allocating operators whose evaluation can safely repeat or disappear.
- Name arguments for parameters used as field, index, method, or call receivers.
- A call in expression position.

The compiler limits code growth and repeated argument computation so inlining
does not make the caller excessively large.
:::

### `OPT-8`, const monomorphization

Calls with known scalar `const` arguments can get specialized versions that
fold constants and unroll bounded loops. The original function remains
available; `-O0` uses only that version.

::: code-group
```nupp [Nupp]
local function accumulate<const N: integer>(value: number, count: N): number
    local total = value
    for offset = 1, count as integer do
        total = total + offset
    end
    return total
end

function m.answer(): number
    return accumulate(10.0, 4)
end
```

```lua [-O1 excerpt]
local function accumulate(value, count)
    local total = value
    for offset = 1, count do
        total = total + offset
    end
    return total
end

local function __nuppConst_accumulate_7f57b563(value)
    local total = value
    do
        do total = total + 1 end
        do total = total + 2 end
        do total = total + 3 end
        do total = total + 4 end
    end
    return total
end

function m.answer()
    return __nuppConst_accumulate_7f57b563(10)
end
```

```lua [-O0]
local function accumulate(value, count)
    local total = value
    for offset = 1, count do
        total = total + offset
    end
    return total
end

function m.answer()
    return accumulate(10, 4)
end
```
:::

The constant must be an `integer`, `boolean`, or `string` and be passed directly
as an argument, as `count` is above.

See [const-specialized
families](ahead-of-time/index.md#const-specialized-families).

::: deepdive Cost heuristics
The compiler limits specialization per module to control code growth;
additional optional specializations stay generic. Calls with equivalent constant
arguments share a specialized version in the function's declaring module. AOT
uses the same limit.

`--remarks` reports calls that stay generic, including those whose checked
bodies are unavailable.
:::

<a id="rewrites-deliberately-not-made"></a>
<a id="loop-closures"></a>

### Rejected rewrites

Define a function outside the loop when every iteration can reuse it.
[`loop-invariant-closure`](../../reference/lints.md#loop-invariant-closure)
suggests eligible cases:

```nupp
local isClick = |event| -> event.kind == "click"
for _, item in ipairs(items) do
    register(item, isClick)
end
```

Suppress intentional cases with `@allow("loop-invariant-closure")`. Closures
that depend on the iteration still block tracing;
[`jit-loop-closure`](jit-trace-checking.md#configurable-source-lint) reports
them when enabled or inside `@jit` functions.

<a id="benchmark-details"></a>

::: deepdive Benchmark details
Measure your own workload with [benchmarks](benchmarks.md) before choosing an
optimization level or disabling a pass.

Recorded local medians, measuring generated code rather than checker time.
Rows use LuaJIT unless marked AOT:

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
| OPT-8, AOT scalar, four rounds over 1,048,576 doubles | 0.001084359s | 0.000512742s | 2.121x faster |
| OPT-8, AOT four lanes, four rounds over 1,048,576 doubles | 0.001084359s | 0.000259625s | 4.176x faster |

Primitive folding, nested propagation, and static callable binding reduced
source size by 32.1%, 60.8%, and 63.6%. Warmed speedups were 0.99x, 2.01x, and
1.06x: hot-loop gains depend on workload and trace shape.

```bash
luajit bench/presize.lua
luajit bench/numeric-ipairs.lua
luajit bench/constant-folding.lua
luajit bench/constant-propagation.lua
luajit bench/static-callable.lua
luajit bench/concat.lua
bench/span-range-lowering/run.sh
bench/kernel-subset-spike/const-monomorph-prototype.sh
```

The `OPT-6` measurements used an arm64 Apple host after warmup, comparing
disabled and enabled passes. Slice results cover derived-view replacement, not
general escape analysis. See `bench/span-range-lowering/README.md` for the full
matrix and `trace.sh` for IR comparisons.

The `OPT-8` rows compare a runtime round count with a specialization for four
rounds, using fifteen paired samples on Apple arm64. Times are medians; speedups
are medians of paired ratios. See [const-monomorphization
measurements](https://github.com/nupp-lang/nupp/blob/c7771128d6c10f06cd6150d0eb625b9ad4a62962/bench/kernel-subset-spike/README.md#const-monomorphization-evidence)
for the recorded run. The script also measures hand-written Lua variants;
those are separate from the compiler-generated AOT results shown here.
:::

## Inspecting, controlling, and measuring

```bash
nupp build -O1 --remarks
nupp build -O1 -Zno-opt=OPT-2
```

`build --remarks` and `run --remarks` report successful and declined rewrites
with source locations. Add `--remarks-file src/work.nupp` to select one source,
and `--remarks-out` to write `build/remarks.json`. Each machine-readable remark
has `status` (`fired`, `declined`, or `unavailable`) and `hotness: "unknown"`:
static decisions do not claim runtime heat. `-O0` reports that optimization is
unavailable instead of silently producing no decisions. Explicit-file builds
write beneath `build/` by default; `-o DIR` changes that directory.

Remarks never fail a build; `check` does not optimize. Use
`-Zno-opt=CODE` to disable one pass or `-O0` to disable all passes. `OPT-n`
codes are stable; `-Z` flags are debugging interfaces.

::: seealso
- [Benchmarks](benchmarks.md): measure changes and set regression gates.
- [Profiling](profiling.md): find where time goes.
- [Trace checking](jit-trace-checking.md): identify recorder blockers in bytecode.
- [Ahead-of-time compilation](ahead-of-time/index.md): compile numeric loops to native code.
:::

## FAQ

<a id="observable-behavior"></a>
<a id="does-o1-change-what-a-program-answers"></a>

### Does `-O1` change how a program works?

No. Optimization preserves results; other observable guarantees require explicit
[`@relax`](../../reference/annotations.md#relaxing-observable-guarantees)
permission to change.

<a id="why-did-a-pass-not-fire-on-code-that-looks-eligible"></a>

### How do I debug why an optimization didn't fire?

Use `--remarks` to see why the compiler left the code unchanged. Common blockers
are mutable bindings and calls whose [effects](../language/effects.md) are
unknown. A helper call that Nupp leaves unchanged may still be inlined by LuaJIT
or the native compiler.

### Why does my `ipairs` loop still use an iterator?

An array type alone does not prove that the loop can safely use numeric
indexing. Writes that change the array's shape, calls with unknown effects,
yields, metatable effects, or a shadowed `ipairs` keep the iterator. See [numeric
`ipairs`](#opt-2-numeric-ipairs) for an eligible loop.

### Why wasn't my loop unrolled?

A known loop bound alone does not request unrolling. Use [const
monomorphization](#opt-8-const-monomorphization) for specialization through
explicit `const` arguments, or [comptime blocks](../language/comptime.md) for
compile-time evaluation.

### Why is this expression still evaluated at runtime?

[Constant folding](#opt-3-constant-folding) leaves floating-point arithmetic,
cdata, calls, and allocations at runtime. Reassigned bindings also stay at
runtime, including those written by nested functions; a separate binding with
the same name does not prevent folding.

### Why wasn't my concatenation loop converted to a buffer?

The string must start as `""`, with one primitive `out = out .. ...` accumulation
and no intervening uses. Reads or captures inside the loop, prepends, multiple
accumulations, and possible `__concat` effects prevent the rewrite.
[Concat buffering](#opt-5-concat-buffer) applies to loops; straight-line
concatenation is unchanged.

### Why do my indexed accesses still have bounds checks?

At `-O0`, accesses keep checked helpers. At `-O1`, held frames, computed indices,
other spans, and accesses outside the validated loop still use those helpers;
the range proof applies only within its function. See [indexed
views](#opt-6-indexed-views) for the supported loop pattern.
