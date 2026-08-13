# Optimization

Nupp leaves ordinary hot-path optimization to LuaJIT. Its own passes target
startup work and facts available only to the checker. The catalog stays small:
a pass lands only with a LuaJIT-enabled benchmark and a static proof that it
preserves behavior. The longer design catalog is in
[`plans/optimizations.md`](../../plans/optimizations.md).

```bash
nupp build -O1
nupp run -O1 --remarks app.nupp
```

`-O1` turns the catalog on and `--remarks` reports what each pass rewrote, or
looked at and declined to rewrite.

## Levels

    nupp build -O1
    nupp run -O1 app.nupp

`-O0` is the default and performs no rewrites. Its generated Lua is the language
semantics with types erased. `-O1` enables every current pass; `-O2` currently
means the same thing and reserves room for a stronger tier later.

The level is part of the build key, so changing it triggers a cold build rather
than mixing artifacts compiled at different levels.

## Passes

| Code | Name | Level | Rewrite |
| --- | --- | --- | --- |
| `OPT-1` | `presize` | -O1 | Size an empty table for the writes about to follow |
| `OPT-2` | numeric-ipairs | -O1 | Use a numeric loop for a proved stable dense array |
| `OPT-3` | constant-fold | -O1 | Fold exact primitives, branches, dead loops, and immutable paths |
| `OPT-4` | static-callable | -O1 | Bind repeated immutable dotted callees at first use |
| `OPT-5` | concat-buffer | -O1 | Append to a string.buffer instead of rebuilding a string each pass |

Each `OPT-n` example below shows Nupp beside its `-O1` and `-O0` output.
Generated temporary names are illustrative.

### Always-on typed call projection

Argument plucking is language lowering rather than an `OPT-n` pass, so it
produces the same flat call at `-O0` and `-O1`. `(name) = path` fills a parameter
from the field of `path` that the parameter names, and `(a, b) = path` fills
several from one operand. Because the operand is confined to a name or dotted
path, the reads are unordered and Nupp can do the table-path sharing ordinary
Lua leaves to hand-written locals or to the trace compiler.

::: code-group
```nupp:static [Readable Nupp]
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

Only reusable path nodes receive locals. One-use projected leaves stay directly
in the positional call. There is no argument table, reflection, varargs pack,
runtime arity choice, generated function, closure, or upvalue. The taken branch
of a safe function or method call has the same flat signature; statement calls
use staged nil guards and returned calls use early returns so plucked paths are
not evaluated when the call is suppressed.

The no-closure rule is deliberate. A call nested where Lua cannot host local
bindings emits repeated direct projections instead:

```nupp:static
local moved = enabled and update(delta, (x, y) = entity.body.position)
```

```lua
local moved = enabled and update(
    delta,
    entity.body.position.x,
    entity.body.position.y
)
```

That may repeat a table prefix, but it is preferable to allocating an
immediately invoked closure and capturing the surrounding values as upvalues.
Native `?.` syntax remains in nested safe calls, preserving lazy argument
evaluation. Statement-position functions, methods, callable records,
constructors, and specialized calls with a known positional pack all reuse the
bind-once plan.

### Always-on table intrinsics

`table.new` and `table.clear` are lowering rather than an `OPT-n` pass: they
work at `-O0` because LuaJIT does not expose them until their builtin modules
are loaded.

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

Each used builtin is bound once per generated module and omitted when unused.
`OPT-1` shares the `table.new` binding. Recognition follows the stable prelude
definition, so a locally shadowed `table` is untouched, and generated modules
remain standalone under external LuaJIT.

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
`string` table. Nupp projects that module through its builtin namespace and
lowers the whole expression to a private `require("string.buffer")` binding;
generated code does not modify the table. Recognition follows the stable
prelude definition, so a locally shadowed `string` is ordinary table access.

Writing the `require` yourself still works. `OPT-5` shares the same private
binding, so a module that both uses `string.buffer` and has an accumulator
lowered requires the module once. Like the table intrinsics this is a lowering
rather than a pass, so it works at `-O0`.

Compiler-only bindings are `const` when the lowering assigns them once. Loop
controls, counters, cache-miss slots, and other mutable storage remain `local`.

### `OPT-1`, presizing

When consecutive named writes reveal an empty table's contents, Nupp moves them
into the constructor. LuaJIT sizes that constructor directly and no
`table.new` call is needed.

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
scan discovered. The scan may step over unrelated statements for that capacity
calculation, but stops when the table is read, escapes, is reassigned, or reaches
a conditional write. Capacity is not observable, so the table otherwise behaves
exactly like `{}`. The win is avoided growth allocations and copying, not a
smaller surviving table.

### `OPT-2`, numeric `ipairs`

A dense literal supplies a static boundary. If effect and alias analysis also
prove that its binding and shape cannot change, Nupp emits a numeric loop over
that binding directly.

::: code-group
```nupp:static [Original Nupp]
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

An array type alone is insufficient. A possible shape-changing write through
any alias, an unknown call, yield, metatable effect, or shadowed `ipairs` keeps
the generic loop. See [effect summaries](../effects.md). The static bound is
intentional; a dynamic raw length was flat or slower after tracing.

### `OPT-3`, constant folding

Folds exact arithmetic, strings, comparisons and boolean selection, propagates
primitive `const` values, resolves branches and loop bounds it can decide, and
reads nested immutable paths. See
[constant folding](constant-folding.md) for each rewrite and what stops it.

### `OPT-4`, static callable binding

Repeated statement-position calls through one immutable path share a local
bound at the first call.

::: code-group
```nupp:static [Original Nupp]
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

The root and every field must be `const`; one call is left alone. First-use
binding preserves lookup order and the error line. Reuse stays within one
lexical block. Labels, `goto`, and calls with specialized FFI, ownership,
construction, or output-parameter lowering are not rewritten.

### `OPT-5`, concat buffer

A string appended to round a loop is built in a `string.buffer` and read back
once, instead of being rebuilt on every pass.

::: code-group
```nupp:static [Original Nupp]
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

This is the one pass here whose win is not a lookup the trace compiler could
have folded. `out = out .. piece` is O(n²), because every pass allocates a
string holding everything so far and interns it, so the work grows with the
length rather than with the count, and a JIT that makes each step fast cannot
make there be fewer steps. `bench/concat.lua` measures 1.8x over eight pieces
rising to 3.6x over sixty-four, still climbing.

The accumulator keeps its own declaration and is assigned back where the loop
closes, so everything after the loop reads an ordinary string and nothing
downstream knows a buffer was involved. Both additions sit on lines that already
belonged to those statements.

The rewrite requires the initializer to be `""`, every mention of the
accumulator inside the loop to be the one `out = out .. ...`, and nothing to
touch the binding between its declaration and the loop. A read of the
half-built string, a capture by a function written in the loop, a prepend
(`out = item .. out`), or a second accumulation each keep the concatenation.
Each `..` must also be one the checker proved primitive: an operand typed `any`
may carry a `__concat` at run time, and `put` would not run it.

Straight-line concatenation is deliberately untouched. Lua performs a
multi-operand concat in one operation, and creating a buffer costs about what
two concatenations cost, so rewriting `a .. b .. c` would be slower.

## Benchmark details

These are fresh local medians with LuaJIT enabled. They measure the exact
generated-Lua shapes shown above, not checker time.

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

Primitive folding reduced its generated input by 32.1%; nested propagation by
60.8%; static callable binding by 63.6%. Warmed results were 0.99x, 2.01x, and
1.06x respectively in this run. Hot results are workload- and trace-dependent,
so the reliable constant and callable wins are smaller source and cold startup.

Run the same benchmarks with:

    luajit bench/presize.lua
    luajit bench/numeric-ipairs.lua
    luajit bench/constant-folding.lua
    luajit bench/constant-propagation.lua
    luajit bench/static-callable.lua

Two more were written before the passes they argue about, which is the point of
them: a benchmark decides whether one is worth writing.

    luajit bench/ffi-hoisting.lua
    luajit bench/concat.lua
    luajit bench/scratch-reuse.lua

`concat` argued for `OPT-5` and now guards it. The other two argued against
passes that are therefore not here. `ffi-hoisting` finds that caching a ctype is
the interpreter's win alone, while the clib symbol binding it also measures is
real and already emitted. `scratch-reuse` finds that hoisting a loop-local table
or `ffi.new` out of its loop is slower than leaving it, because allocation
sinking already removes an allocation that does not escape its trace, which is
the same condition a pass would have had to prove. All three exit non-zero if
their finding stops holding, so the ones that argue against a pass keep arguing.

## Inspecting and controlling passes

    nupp build -O1 --remarks
    nupp build -O1 -Zno-opt=OPT-2

`--remarks` reports both successful rewrites and declined proofs, including the
source location that stopped an analysis. Remarks are notes and never fail a
build. They are available from `build` and `run`; `check` does not optimize.

`-Zno-opt=CODE` disables one pass for miscompile bisection. Pass codes are
stable, but the `-Z` spelling is an unstable debugging interface. Use `-O0` to
disable every rewrite.

## Deliberately left in source

Nupp does not cache a closure created inside a loop: that changes function
identity. The `loop-invariant-closure` lint instead suggests lifting a closure
that does not depend on the iteration.

```nupp:static
local isClick = |event| -> event.kind == "click"
for _, item in ipairs(items) do
    register(item, isClick)
end
```

Suppress an intentional case with `@allow("loop-invariant-closure")`; see
[lints](../lints.md).

## Observable behavior

Current passes change nothing observable. Optimizations that would trade a
guarantee for speed must explicitly check a named `--relax` or `@relax`
permission. The compiler fixpoint verifies the standing claim: compiling the
compiler at `-O1` must produce output byte-identical to compiling it at `-O0`.

## Next

- [Constant folding](constant-folding.md): each rewrite `OPT-3` makes, and
  what stops it.
- [Profiling](profiling.md): where the time actually goes, before deciding a
  pass would help.
