# Performance

What makes a Nupp program fast, and where each part is specified.

LuaJIT's trace compiler does the hot-path work, so most of what follows is
either something the checker knows that LuaJIT cannot, or a shape chosen so a
trace forms at all. Nothing here is a language promise about timing: thresholds
are measured implementation details, and every rewrite preserves answers.

- **Always-on lowerings** need no flag. Typed call projection, the table and
  `string.buffer` intrinsics, and switch dispatch all work at `-O0`.
- **The `-O1` pass catalog** adds six rewrites, each of which had to land with a
  LuaJIT-enabled benchmark and a static proof. See
  [Optimization](optimization.md) for the levels, the `OPT-n` catalog, remarks,
  and per-pass controls.
- **Per-feature fast paths** — switch dispatch, indexed views, and SoA hot loops
  — are documented below.
- **[Ahead-of-time compilation](aot.md)** compiles a narrow scalar subset to
  native code when the Lua backend is not enough.

## Switch dispatch

A [switch expression](../switch-expressions.md) lowers to lexical
selector/result locals and an ordered `if`/`elseif` chain. It does not wrap the
switch in an immediately invoked function, so writing one in a hot loop adds no
function-construction bytecode that would abort and blacklist LuaJIT traces.
Type-case bindings reuse the one selector local, so a computed selector is never
repeated for `is` or field loads.

Some static switches can finish the decision with one compiler-owned table read.
This is deliberately narrower than "every arm is an expression": every case and
result, including `else`, must be one compiler-known inert scalar. A dynamic
expression still runs only after its case is selected and therefore keeps the
lexical branch lowering:

```nupp
-- Branches: formatStatus must run only for the selected arm.
local shown = switch status do
    case 200 -> formatStatus(status)
    case 301 -> "redirect"
    else -> "other"
end
```

A sufficiently large eligible map may use a dense integer array or a table keyed
by sparse integers or strings:

```nupp
-- Five labels in a span of five are eligible for a dense array.
local category = switch byte do
    case 9 -> "tab"
    case 10 -> "newline"
    case 11 -> "vertical tab"
    case 12 -> "form feed"
    case 13 -> "return"
    else -> "other"
end

-- Sixteen labels spread over a much wider span are eligible for a sparse map.
local retry = switch status do
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

-- Eight strings meet the string-map floor. This map needs a nil sentinel.
local keyword = switch word do
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

The table is allocated once in generated module setup, never at the switch site.
A missing key is already `nil`, so integer maps perform no range guard and holes
need no placeholder. An arm which itself produces `nil` is the exceptional case:
generated data uses a private sentinel to distinguish that hit from a miss, and
the sentinel is omitted from every map without a nil result.

Coverage builds always retain ordered branches because each authored case needs
one instrumentable condition. Branches are also kept for small maps, block arms,
destructuring, contextual `yield`, early `return`, refinements, any result whose
evaluation can be observed, and a nested switch in an arm — which cannot be a
static result-map entry, though the inner switch may still use its own plan.
Exact thresholds are measured implementation details rather than language
promises.

Record cases use nominal metatable identity. When checking proves that the
remaining selector is entirely records, lowering reads `__index` without a
safe-navigation guard and may share that identity read across a leading run of
record cases. An optional, gradual, primitive, refined, or otherwise open
selector keeps the guarded or authored-order predicate.

In the [AOT](aot.md) scalar subset, a switch that initializes one scalar local,
uses integer-valued numeric cases, has expression arms, and is checker-proven
exhaustive is admitted. An established `int32` or `uint32` selector is emitted as
native C `switch`, and the C compiler decides whether that becomes branches, a
tree, bit tests, or a jump table; an ordinary binary64 selector retains equality
branches because converting it would change semantics.

There is no per-dispatch C helper, function table, BDD, MTBDD, perfect hash, or
LuaJIT VM extension. Stock LuaJIT cannot jump from a computed case ordinal to an
arbitrary lexical arm, so a lookup is used only when it is the end of the
decision rather than the start of a second dispatch.

## Indexed views and ranges

[`indexed.range`](../spans.md#one-range-for-several-spans) checks one inclusive
range against every participating trusted Span or SoA view. The successful check
proves matching indexed reads and writes non-raising inside the dominated
numeric loop, and that proof is part of checking at every optimization level —
it is what permits those calls inside `noraise` code.

At `-O1` the regular backend also spends the proof, emitting direct FFI element
access for the exact span and bare loop index. The range call still validates
every span once, and the generated access still includes the span's physical
offset. `-O0`, held frames, a computed index, a different span, or an access
outside the witnessed loop retains one checked helper operation. The proof is
local to the function containing `indexed.range`; passing its bounds or result to
another function does not transport it.

Also at `-O1`, a nonescaping const slice used only by proved indexed operations
can remain virtual: Nupp keeps its checked finish, root, offset, count, and
access capability as compiler facts instead of allocating the slice wrapper.
Nested slices compose offsets, while the bounds check still executes once at each
authored `slice` expression. The same scalar representation starts at
`fromString`, the shared and writable C-array constructors, and
`heap.Array:read()` or `heap.Array:write()`. Directly called, nonrecursive local
functions in the same module can receive and return a virtual view without
allocating a wrapper. Returning, capturing, storing, or passing the slice to an
unsupported call — and exported, recursive, dynamic, foreign, cross-module, and
otherwise opaque boundaries — use the materialized ABI.

`OPT-6` in [Optimization](optimization.md) covers the pass mechanics, its
remark, and the benchmark matrix behind it.

## Structure-of-arrays hot loops

The canonical loop `for index = 1, #rows` proves every indexed row access into a
[SoA view](../soa.md) is in bounds. Nupp lowers fields inside that loop to direct
typed-column loads and stores using the view offset; an arbitrary index keeps its
runtime bounds check.

No profiler call is injected into the loop. `nupp bc --check FILE` inspects the
lowered bytecode without executing it.

An [`@aot`](aot.md) function retains the same resolved field identities and
single-map-loop fact. A borrowed kernel names the writable capability
intersection rather than the affine owner alias:

```nupp
@aot
local function advance(
    exclusive rows: soa.WriteToken & soa.WriteSpan<Particle>,
    delta: float
): nil
    for index = 1, #rows do
        rows[index].x += rows[index].dx * delta
        rows[index].y += rows[index].dy * delta
    end
end
```

The AOT backend retains those field identities and unit strides in its IR for
direct scalar or lane lowering. `nupp aot` can display the lowered artifacts;
`nupp build` still emits the ordinary Lua body until object integration is wired
into production builds.

## Strings, tables, and calls

These are always-on lowerings and `-O1` passes rather than per-feature paths, so
[Optimization](optimization.md) specifies them in full. In summary:

- Typed call projection flattens `(a, b) = path` arguments with no argument
  table, closure, or upvalue, at every level.
- `table.new`, `table.clear`, and `string.buffer` are bound once per generated
  module, at every level.
- `OPT-1` moves consecutive named writes into the table constructor so LuaJIT
  sizes it directly.
- `OPT-5` rewrites a string accumulated round a loop into a `string.buffer`,
  turning an O(n²) rebuild into appends.

Nupp does not cache a closure created inside a loop, because that changes
function identity; the `loop-invariant-closure` lint suggests lifting one that
does not depend on the iteration.

## Measuring

Measure before deciding any of this matters:

- [Profiling](profiling.md) says where the time actually goes.
- [LuaJIT trace checking](jit-trace-checking.md) and `nupp bc --check FILE` find
  recorder blockers in the exact generated bytecode, without a quiet machine and
  without executing anything.
- `nupp build -O1 --remarks` reports what each pass rewrote, or looked at and
  declined to rewrite.
- `bench/` holds the LuaJIT-enabled benchmarks behind every pass, including the
  three that argued against passes that were therefore never written.

## Next

- [Optimization](optimization.md): the `-O` levels, the `OPT-n` catalog, and the
  benchmark behind each pass.
- [Ahead-of-time compilation](aot.md): the native scalar subset and its
  boundaries.
