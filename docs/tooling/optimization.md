# Optimization

Nupp leaves ordinary hot-path optimization to LuaJIT; its own passes target
startup work and facts available only to the checker. A pass lands only with a
LuaJIT-enabled benchmark and a static proof that it preserves behavior. The
design catalog is
[`plans/014-optimizations.md`](../../plans/014-optimizations.md), and
[LuaJIT trace checking](jit-trace-checking.md) finds recorder blockers.

```bash
nupp build -O1
nupp run -O1 --remarks app.nupp
```

`-O1` turns the catalog on; `--remarks` reports what each pass rewrote, or
looked at and declined to rewrite.

## Levels

    nupp build -O1
    nupp run -O1 app.nupp

`-O0`, the default, rewrites nothing: its generated Lua is the language
semantics with types erased. `-O1` enables every current pass; `-O2` means the
same today and reserves room for a stronger tier later. The level is part of the
build key, so changing it triggers a cold build.

## Passes

| Code | Name | Level | Rewrite |
| --- | --- | --- | --- |
| `OPT-1` | `presize` | -O1 | Size an empty table for the writes about to follow |
| `OPT-2` | numeric-ipairs | -O1 | Use a numeric loop for a proved stable dense array |
| `OPT-3` | constant-fold | -O1 | Fold exact primitives, branches, dead loops, and immutable paths |
| `OPT-4` | static-callable | -O1 | Bind repeated immutable dotted callees at first use |
| `OPT-5` | concat-buffer | -O1 | Append to a string.buffer instead of rebuilding a string each pass |
| `OPT-6` | indexed-range | -O1 | Select proved direct access and scalar-replace indexed views |

Each `OPT-n` example below shows Nupp beside its `-O1` and `-O0` output.
Generated temporary names are illustrative.

### Always-on typed call projection

Argument plucking is lowering rather than a pass, so the flat call is the same
at `-O0` and `-O1`. `(name) = path` fills a parameter from the field of `path`
that it names; `(a, b) = path` fills several from one operand. The operand is
confined to a name or dotted path, so the reads are unordered and the table path
can be shared.

::: code-group
```nupp [Readable Nupp]
local record Vec2
    x: number
    y: number
end

update(delta, (x, y) = entity.body.position, (dx, dy) = entity.body.velocity)
```

```lua [Generated Lua]
const __nupp_body = entity.body
const __nupp_position = __nupp_body.position
const __nupp_velocity = __nupp_body.velocity
update(
    delta,
    __nupp_position.x,
    __nupp_position.y,
    __nupp_velocity.x,
    __nupp_velocity.y
)
```
:::

Only reusable path nodes receive locals; one-use leaves stay in the positional
call. There is no argument table, reflection, varargs pack, runtime arity
choice, generated function, closure, or upvalue, and safe calls keep the same
flat signature — statement calls use staged nil guards, returned calls early
returns — so plucked paths are not evaluated when the call is suppressed.

Nested where Lua cannot host local bindings, the projection repeats rather than
allocate an immediately invoked closure and capture upvalues:

```nupp
local moved = enabled and update(delta, (x, y) = entity.body.position)
```

```lua
local moved = enabled and update(
    delta,
    entity.body.position.x,
    entity.body.position.y
)
```

Native `?.` remains in nested safe calls, preserving lazy argument evaluation.
Statement-position functions, methods, callable records, constructors, and
specialized calls with a known positional pack reuse the bind-once plan.

### Always-on table intrinsics

`table.new` and `table.clear` are lowering rather than a pass, and so work at
`-O0`, because LuaJIT does not expose them until their builtin modules are
loaded.

::: code-group
```nupp [Original Nupp]
local cache = table.new(128, 8)
cache.ready = true
table.clear(cache)
```

```lua [Generated Lua]
const __nuppNew = require("table.new")
const __nuppClear = require("table.clear")
local cache = __nuppNew(128, 8)
cache.ready = true
__nuppClear(cache)
```
:::

Each used builtin is bound once per generated module and omitted when unused;
`OPT-1` shares the `table.new` binding. Recognition follows the stable prelude
definition, so a shadowed `table` is untouched and generated modules stay
standalone under external LuaJIT.

Inside a VM-aware `@aot` builder the same identity lowers natively: capacities
are checked and passed to `lua_createtable`, writes to the still-fresh table use
public raw-set API calls, and table literals carry inferred array/hash
capacities — `nupp aot --json` reports `entryMode: "lua-builder"`. Allocation
alone is not a reason to add `@aot`; profile the construction loop first.

### `string.buffer` builtin

`string.buffer` is reachable through the builtin `string` namespace with no
source-level `require`:

::: code-group
```nupp [Original Nupp]
local b = string.buffer.new()
b:put("a", "b")
return b:tostring()
```

```lua [Generated Lua]
const __nuppBuffer = require("string.buffer"); local b = __nuppBuffer.new()
b:put("a", "b")
return b:tostring()
```
:::

LuaJIT keeps the module in `package.loaded` and puts nothing on the runtime
`string` table, so Nupp lowers the whole expression to a private
`require("string.buffer")` binding rather than modifying that table; a shadowed
`string` is ordinary table access. Writing the `require` yourself still works,
and `OPT-5` shares the binding, so a module doing both requires it once. Like
the table intrinsics this is lowering, so it works at `-O0`.

Compiler-only bindings are `const` when the lowering assigns them once. Loop
controls, counters, cache-miss slots, and other mutable storage remain `local`.

### `OPT-1`, presizing

Consecutive named writes that reveal an empty table's contents move into the
constructor, which LuaJIT sizes directly with no `table.new` call.

::: code-group
```nupp [Original Nupp]
local point = {}
point.x = 1
point.y = 2
point.z = 3
```

```lua [Optimized Lua]
local point = {
    x = 1,
    y = 2,
    z = 3,
}
```

```lua [Unoptimized Lua]
local point = {}
point.x = 1
point.y = 2
point.z = 3
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
```nupp [Original Nupp]
local xs: {integer} = {10, 20, 30}
for index, value in ipairs(xs) do
    use(index, value)
end
```

```lua [Optimized Lua]
local xs = {10, 20, 30}
for index = 1, 3 do
    local value = xs[index]
    use(index, value)
end
```

```lua [Unoptimized Lua]
local xs = {10, 20, 30}
for index, value in ipairs(xs) do
    use(index, value)
end
```
:::

An array type alone is insufficient: a possible shape-changing write through any
alias, an unknown call, yield, metatable effect, or shadowed `ipairs` keeps the
generic loop — see [effect summaries](../effects.md). The static bound is
intentional; a dynamic raw length was flat or slower after tracing.

### `OPT-3`, constant folding

`OPT-3` evaluates what it can at compile time and propagates the result, so a
value a reader can work out is not one the program works out on every run:

```nupp:playground
local m = {}

const WIDTH: integer = 8

function m.area(): integer
    return WIDTH * 4
end

return m
```

`m.area` lowers to `return 32`. Each rewrite, and what declines it, follows.

#### Exact primitives and local propagation

Exact integer arithmetic, strings, comparisons, and boolean selection fold;
primitive `const` values propagate through later expressions.

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

#### Integer division and the bit operators

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

A zero divisor keeps the division: its answer is an infinity, not an integer.

`&`, `|`, `~`, `<<`, `>>` and `~>>` fold through BitOp, which is their declared
meaning rather than an approximation of it: operands normalize to 32 bits and
results come back signed, so the folded answers are the surprising ones.

```nupp
const FLAGS = 1 << 3 | 1 -- 9
const WRAP = 1 << 32 -- 1, a shift count being taken modulo 32
const LOG = -8 >> 1 -- 2147483644, the plain shift being logical
const AR = -8 ~>> 1 -- -4, the tilde shift being arithmetic
```

Folding runs the same primitive the emitted operator would have, so the two
cannot disagree by construction; the test sweeps one against the other anyway.

#### Loops that cannot run

A loop whose constant bounds admit no first iteration is not emitted; the empty
`do` left behind compiles to nothing.

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

A step of zero is left alone: `for i = 1, 10, 0` does not terminate, and
removing it would remove the hang rather than the cost of it.

#### Constant branches

If every tested condition is constant, only the selected arm is emitted; a `do`
preserves the arm's original scope.

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

#### Nested immutable paths

`const M = {}` fixes the module-table binding, not the table. `const M.field`
fixes one named slot, leaving ordinary fields mutable; `const... M.field` is the
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
immutable; one mutable parent keeps the read intact. `require` is never removed
or moved, because loading a module may have effects. No `module` keyword or
runtime freezing is involved: `const` records the checked, shallow guarantee and
`const...` applies it recursively to fresh named fields. See
[comptime types](../type-system/type-level-computation.md) for the binder.

### `OPT-4`, static callable binding

Repeated statement-position calls through one immutable path share a local
bound at the first call.

::: code-group
```nupp [Original Nupp]
const service = require("service")
service.x.y()
service.x.y()
```

```lua [Optimized Lua]
const service = require("service")
const __nupp_call_1 = service.x.y; __nupp_call_1()
__nupp_call_1()
```

```lua [Unoptimized Lua]
const service = require("service")
service.x.y()
service.x.y()
```
:::

The root and every field must be `const`, and one call is left alone. First-use
binding preserves lookup order and the error line; reuse stays within one
lexical block. Labels, `goto`, and calls with specialized FFI, ownership,
construction, or output-parameter lowering are not rewritten.

### `OPT-5`, concat buffer

A string appended to round a loop is built in a `string.buffer` and read back
once, instead of being rebuilt on every pass.

::: code-group
```nupp [Original Nupp]
local out = ""
for _, item in ipairs(items) do
    out = out .. item .. ","
end
return out
```

```lua [Optimized Lua]
const __nuppBuffer = require("string.buffer"); local out = "" local __nuppBuf_1 = __nuppBuffer.new()
for _, item in ipairs(items) do
__nuppBuf_1:put(item, ",")
end out = __nuppBuf_1:tostring()
return out
```

```lua [Unoptimized Lua]
local out = ""
for _, item in ipairs(items) do
out = out .. item .. ","
end
return out
```
:::

`out = out .. piece` is O(n²) — every pass allocates and interns a string
holding everything so far — so this is the one win here the trace compiler could
not have folded itself. `bench/concat.lua` measures 1.8x over eight pieces
rising to 3.6x over sixty-four, still climbing.

The accumulator keeps its declaration and is assigned back where the loop
closes, so everything after it reads an ordinary string, and both additions sit
on lines that already belonged to those statements. The rewrite requires the initializer to be `""`, every mention inside the loop
to be the one `out = out .. ...`, and nothing to touch the binding between
declaration and loop. A read of the half-built string, a capture by a function
written in the loop, a prepend (`out = item .. out`), or a second accumulation
keeps the concatenation, as does a `..` the checker did not prove primitive: an
`any` operand may carry a `__concat`, which `put` would not run.

Straight-line concatenation is untouched — Lua concatenates multiple operands in
one operation, and a buffer costs about what two concatenations cost.

### `OPT-6`, trusted indexed range access

`indexed.range` validates an inclusive range against each participating trusted
Span or SoA view; a canonical `for index = 1, #view` loop proves the same fact
for that exact view. `OPT-6` then selects the view's physical adapter instead of
repeating each indexed access's checks.

::: code-group
```nupp [Original Nupp]
const rows = indexed.range(first, last, output, input)
for index = rows.first, rows.last do
    output[index].x = input[index].x + 1
end
```

```lua [Optimized Lua]
local rows = indexed.range(first, last, output, input)
for index = rows.first, rows.last do
    output.pointer[output.offset + index - 1].x =
        input.pointer[input.offset + index - 1].x + 1
end
```

```lua [Unoptimized Lua]
local rows = indexed.range(first, last, output, input)
for index = rows.first, rows.last do
    output:get(index).x = input:get(index).x + 1
end
```
:::

The range failure remains at `indexed.range`, whose success already proves the
removed bounds error cannot occur; `noraise` consumes that proof independently.

Witness, spans, and loop are matched by checked declaration identity within one
function: both bounds must be the same const range's bare `.first` and `.last`,
the step implicit, and each span const-bound when the range was formed.
Arbitrary indexes, spans omitted from the range, nested functions, lookalike
methods, and writes through an unproved index keep the checked operation. The
generated expression reaches `pointer` and `offset` through the span, preserving
roots and nonzero slice offsets; pointer hoisting is not part of it.

The pass also scalar-replaces exact standard roots and const derived views whose
complete use set is proved: `span.fromString`, the shared and writable C-array
constructors, `heap.Array:read()`/`write()`, and `soa.Array:read()`/`write()`.
Slices retain one checked finish scalar, shared downgrades their count, resolved
SoA field projections select the column directly, and nested combinations
compose offsets without wrapper tables. Dynamic base, offset, count, and column
expressions are captured once in source order, and constructor validation,
exclusive acquisition, dirty marking, and other producer effects still execute
once. Access stays rooted through the source owner, so scalar replacement cannot
detach a pointer or column from its anchor; `-O0`, an escape, or an unsupported
operation preserves the checked runtime object.

Directly called, nonrecursive local functions in the same checked module may
transport an admitted view through parameters or one return value as flattened
runtime state. Recursive, exported, dynamic, foreign, cross-module, `any`, and
otherwise opaque boundaries retain the materialized ABI.

One remark is aggregated per loop:

    OPT-6 indexed-range: lowers 2 span accesses

Disable the pass alone with `-Zno-opt=OPT-6`.

## Benchmark details

Fresh local medians with LuaJIT enabled, measuring the exact generated-Lua
shapes shown above rather than checker time.

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

## Inspecting and controlling passes

    nupp build -O1 --remarks
    nupp build -O1 -Zno-opt=OPT-2

`--remarks` reports both successful rewrites and declined proofs, including the
source location that stopped an analysis. Remarks never fail a build; they come
from `build` and `run`, and `check` does not optimize. `-Zno-opt=CODE` disables
one pass for miscompile bisection — the codes are stable, the `-Z` spelling is
an unstable debugging interface — and `-O0` disables every rewrite.

## Deliberately left in source

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

`nupp bc --check FILE` checks the generated bytecode without executing it. A
blocker every back edge must reach fails CI; one only some paths reach is
reported without claiming the loop can never form another trace. JSON includes
the bytecode fingerprint, trace profile, stable reason identity, and
reachability.

## Observable behavior

Passes preserve answers. One that trades a non-answer guarantee for speed must
explicitly check a named `--relax` or `@relax` permission; `OPT-6` requires
`frames`. The compiler fixpoint verifies that compiling the compiler at `-O1`
produces output byte-identical to compiling it at `-O0` while its guarantees are
held.

## Next

- [Comptime types](../type-system/type-level-computation.md): the `const` binder
  `OPT-3` reads.
- [Profiling](profiling.md): where the time actually goes, before deciding a
  pass would help.
