# Ahead-of-time compilation

`@aot` marks a whole function to be compiled ahead of time rather than left to
LuaJIT. The compiler admits a small structural subset, lowers it to a verified
IR, and emits private C — and where the function is one numeric map loop, it
also rewrites that loop to run several iterations at once. Nothing in the source
names a lane, a mask, or a vector width.

**Status.** The backend is implemented and lives under
`src/nupp/compiler/aot/`. It is not wired into `nupp build`: production builds
still emit the ordinary Lua body, and there is no `nupp aot` command. The
driver that runs the backend end to end is test-only, under
`bench/kernel-subset-spike/`. Everything below is real output from that driver
on the committed kernels; the commands are the ones the repository actually
has today. What `nupp build` will do with an `@aot` function — artifact
policy, target dispatch, caching, inspection — is not decided yet.

What already ships is the front half: `nupp check` validates the target and the
structural subset, so `@aot` on something the backend could not compile is an
error today rather than a surprise later.

## What the annotation buys

Three things, in order of how much they matter.

The body compiles once, ahead of time, with a real optimizing compiler behind
it. LuaJIT is very good, but it is a tracing JIT: it compiles what it observes,
it gives up on shapes it cannot record, and a hot loop that aborts a trace runs
interpreted however hot it gets.

The body's numeric meaning is pinned. Ordinary Nupp arithmetic is binary64 and
is neither contracted nor reassociated, so an AOT function's answers are a
property of what was written rather than of the target that compiled it. Where
you want a relaxation you ask for it, per function, with `@relax`.

And a body that is one map loop over spans may be lowered lane-parallel. That
is the largest single win where it applies, and the compiler decides whether it
applies.

## A worked example

This is `bench/kernel-subset-spike/mandelbrot.nupp`, trimmed to its shape. It
is ordinary Nupp — spans, structs, a `while` loop with a `break`:

```nupp
local span = require("nupp.span")

local struct Point
    re: float
    im: float
end

local struct Escape
    iterations: int32
    escaped: uint32
end

@relax("fp-contract")
@aot
local function mandelbrot(
    exclusive escapes: span.WriteSpan<Escape>,
    borrows points: span.Span<Point>,
    first: integer,
    last: integer,
    maxIterations: int32
): nil
    if escapes.count ~= points.count then
        error("length mismatch", 2)
    end
    if first < 1 or last > escapes.count or first > last + 1 then
        error("range out of bounds", 2)
    end

    for i = first, last do
        local escape = escapes:getMut(i)
        local point = points:get(i)
        local cx = point.re
        local cy = point.im
        local zx = 0.0
        local zy = 0.0
        local zxSquared = 0.0
        local zySquared = 0.0
        local iteration = 0
        local escaped = 0
        while iteration < maxIterations do
            if zxSquared + zySquared > 4.0 then
                escaped = 1
                break
            end
            zy = 2.0 * zx * zy + cy
            zx = zxSquared - zySquared + cx
            zxSquared = zx * zx
            zySquared = zy * zy
            iteration = iteration + 1
        end
        escape.iterations = iteration
        escape.escaped = escaped
    end
end
```

Two guards, then one numeric `for` loop. That shape is not decoration: the
length guard is what proves the two spans can share one index, and the range
guard is what lets the generated loop read its bounds without re-checking them
every element.

Compile and run it:

```bash
bench/kernel-subset-spike/mandelbrot.sh mandelbrot
```

```bash
MANDELBROT_WIDTH=1024 MANDELBROT_HEIGHT=768 MANDELBROT_ITERATIONS=256 \
    luajit bench/kernel-subset-spike/mandelbrot_main.lua
```

To stop after the C so you can read it:

```bash
NUPP_NATIVE_MODE=emit-c bench/kernel-subset-spike/mandelbrot.sh mandelbrot
```

## The generated C

### Layouts, stated and checked

Every reified struct becomes a C type, and the object exports what its own C
compiler decided about the layout:

```c
typedef struct {
    int32_t iterations;
    uint32_t escaped;
} KsEscape;

size_t ks_mandelbrot_layout_Escape_size(void) { return sizeof(KsEscape); }
size_t ks_mandelbrot_layout_Escape_offset_iterations(void) { return offsetof(KsEscape, iterations); }
size_t ks_mandelbrot_layout_Escape_size_iterations(void) { return sizeof(((KsEscape *)0)->iterations); }
```

Those exist so the generated wrapper can compare them against `layoutof` at
load, before anything is callable. Reifying a struct is a claim about memory,
and this is where the claim is tested rather than assumed.

### The scalar body

The tail loop — and the whole body when lane lowering declines — is a direct
transcription:

```c
    for (; i < end; ++i) {
        KsEscape *v1_escape = (&p_escapes[i]);
        const KsPoint *v2_point = (&p_points[i]);
        double v3_cx = ((double)(v2_point->re));
        double v4_cy = ((double)(v2_point->im));
```

Two things worth reading closely. `p_escapes` is `KsEscape *restrict` and
`p_points` is `const KsPoint *` — that is the alias matrix ownership already
proved, restated where the C compiler can use it, not something recovered from
the pointer types. And `(double)(v2_point->re)` is a physical load widening: a
`float` field is storage, so reading one gives an ordinary Nupp number. That is
the only place a width changes without the source asking.

### The lane-parallel body

The same loop, four iterations at a time. Vector types are C vector extensions,
so an elementwise operation is written as though it were scalar:

```c
typedef long long ks_m64x4 __attribute__((vector_size(32)));
typedef double ks_f64x4 __attribute__((vector_size(32)));

static inline ks_f64x4 ks_splat_f64x4(double v) { return (ks_f64x4){v, v, v, v}; }
static inline ks_f64x4 ks_sel_f64x4(ks_m64x4 m, ks_f64x4 a, ks_f64x4 b) {
    return (ks_f64x4)((m & (ks_m64x4)a) | (~m & (ks_m64x4)b));
}
```

```c
    size_t groups = (end > i) ? ((end - i) / 4) * 4 + i : i;
    for (; i < groups; i += 4) {
        ks_f64x4 v3_cx = ((ks_f64x4){p_points[i + 0].re, p_points[i + 1].re,
                                     p_points[i + 2].re, p_points[i + 3].re});
        ks_f64x4 v9_zx = ks_splat_f64x4(0.0);
        ks_m64x4 lm4_live = (v13_iteration < ks_splat_f64x4(((double)p_maxIterations)));
        while (ks_any(lm4_live)) {
            ks_m64x4 lm5_exec = lm4_live;
            ks_m64x4 lm6_if = (lm5_exec & ((v11_zxSquared + v12_zySquared) > ks_splat_f64x4(4.0)));
            v14_escaped = ks_sel_f64x4((lm6_if & lm5_exec), ks_splat_f64x4(1.0), v14_escaped);
            lm4_live &= ~((lm6_if & lm5_exec));
            lm5_exec &= ~((lm6_if & lm5_exec));
            v10_zy = (((ks_splat_f64x4(2.0) * v9_zx) * v10_zy) + v4_cy);
            v9_zx = ((v11_zxSquared - v12_zySquared) + v3_cx);
            v11_zxSquared = (v9_zx * v9_zx);
            v12_zySquared = (v10_zy * v10_zy);
            v13_iteration = ks_sel_f64x4(lm5_exec, (v13_iteration + ks_splat_f64x4(1.0)), v13_iteration);
            lm4_live &= (v13_iteration < ks_splat_f64x4(((double)p_maxIterations)));
        }
```

Read what happened to the source's control flow. The `if` became a mask. The
`break` became `lm4_live &= ~mask` — the lane retires from the loop instead of
branching out of it, and the loop ends when `ks_any` says nothing is live. The
assignment to `iteration` became a select, so a lane that already escaped keeps
what it had.

`live` and `exec` are two masks because they differ: a lane that hit `continue`
is not running the rest of this iteration but is still in the loop.

The store writes consecutive elements one lane each, which Clang turns into an
interleaving store where the target has one:

```c
        {
            ks_f64x4 lanes = v13_iteration;
            p_escapes[i + 0].iterations = (int32_t)lanes[0];
            p_escapes[i + 1].iterations = (int32_t)lanes[1];
            p_escapes[i + 2].iterations = (int32_t)lanes[2];
            p_escapes[i + 3].iterations = (int32_t)lanes[3];
        }
    }
```

The remainder runs the scalar body one iteration at a time rather than a masked
final group. A masked load still reads the addresses it masked off, and the last
element of a span may be the last byte of a page.

Two whole functions come out: `ks_mandelbrot`, and `ks_mandelbrot_forced_scalar`
carrying a pragma that refuses vectorisation. The second is the oracle the first
is diffed against, and it must not share its lowering — including whatever the C
compiler would have done on its own.

### The wrapper

The generated Nupp module is what a caller sees. Ownership survives; the
pointers do not escape:

```nupp
local function mandelbrot(
    exclusive escapes: span.WriteSpan<Escape>,
    borrows points: span.Span<Point>,
    first: integer,
    last: integer,
    maxIterations: int32
): nil
    if first < 1 or last > escapes.count or first > last + 1 then
        error("native range out of bounds", 2)
    end
    local native_escapes, native_escapesCount = escapes:ref()
    local native_points, native_pointsCount = points:ref()
    if native_pointsCount ~= native_escapesCount then
        error("native spans have incompatible lengths", 2)
    end
    unsafe do
        ks_mandelbrot(native_escapes as voidptr, native_points as voidptr,
            first, last, maxIterations, native_escapesCount)
    end
end
```

The range check and the length agreement are ordinary checked Nupp; `unsafe do`
holds the foreign call and nothing else.

## Benchmarks

Apple arm64, 1024×768 grid, 256 iterations, `clang -O3`. All three rows run the
same function on the same inputs and are checked to agree on every pixel — this
measures how the body was compiled and nothing else.

```
 Body                     ns/frame      MPix/s   Relative
 ───────────────────────  ───────────  ────────  ────────
 AOT, lane-parallel        10,465,198     75.15      30.4x
 AOT, forced scalar        21,268,854     36.98      15.0x
 LuaJIT                   318,066,750      2.47       1.0x
```

Reproduce with:

```bash
MANDELBROT_WIDTH=1024 MANDELBROT_HEIGHT=768 MANDELBROT_ITERATIONS=256 \
    MANDELBROT_QUIET=1 luajit bench/kernel-subset-spike/mandelbrot_main.lua
```

Read the two gaps separately, because they have different causes.

**Lane-parallel over scalar C is 2.0×** on four lanes. Not 4×: lanes diverge.
Every lane runs until the last one escapes, so a group costs its slowest member.

**Scalar C over LuaJIT is 15×**, and most of that is not arithmetic. Timing the
same recurrence in plain Lua with local variables instead of spans gives about
4.6 MPix/s, so roughly half the gap is the span and struct-field plumbing that
the AOT body compiles away and the interpreter cannot. The rest is codegen on a
loop with a data-dependent exit. The loop is traceable — `nupp bc --check` on
this kernel is clean — so this is LuaJIT compiling it and still losing, not
LuaJIT giving up.

The same program written in explicit binary32 gets eight lanes for the same
registers:

```
 Body                     MPix/s   Notes
 ───────────────────────  ───────  ─────────────────────────────
 AOT f32x8                 123.28  eight lanes, 32-byte gang
 AOT forced scalar          35.66  same width as the f64 scalar
 LuaJIT                      0.02  every rounding through an FFI store/load
```

That is a different program with different escape counts, and it is the source
that says so. The LuaJIT row collapses because explicit binary32 in ordinary
Nupp performs each rounding point through an FFI store and load — which is the
price of the source, not an artifact of measuring it.

## Automatic vectorisation

### What the compiler decides

Lane lowering is attempted for every `@aot` body whose shape admits it. Two
decisions follow, both made from the loop itself.

**Whether it pays.** Lane lowering wins where a loop stays in registers and
loses where it streams memory: Mandelbrot runs about twice its scalar speed,
while a component update runs between a tenth and four fifths of its. Neither
layout nor element width moves that. What separates them is how much arithmetic
there is to amortize assembling and taking apart the vectors, so the estimate is
arithmetic operations per byte the body touches, with a threshold of 1.0.

**How wide.** Both gangs are 32 bytes, so a group costs the same registers
either way and only the lane count differs. Ordinary Nupp arithmetic is
binary64, so a loop written with operators gets four lanes. A loop whose varying
values are all 32-bit — because the source asked for binary32 or wrapping int32
through the released `nupp.math` namespaces — gets eight. The widest gang is
tried first and refuses the moment any varying value turns out to be binary64.

You can see both answers per kernel:

```bash
bench/kernel-subset-spike/generate.sh bench/kernel-subset-spike/mandelbrot.nupp \
    /tmp/out --check-lanes
```

```
 Kernel              Ops/byte   Outcome
 ──────────────────  ─────────  ──────────────────────────
 mandelbrot.nupp          5.19  lowered to 4 lanes
 mandelbrot_f32.nupp      5.12  lowered to 8 lanes
 kernels.nupp             0.39  declined, too little arithmetic
 columns.nupp             0.17  declined, too little arithmetic
 tecsbits.nupp            0.43  lowered to 4 lanes, by request
 corrected.nupp           0.12  lowered to 8 lanes, by request
```

The last two are below the threshold and lowered anyway, because their source
says so.

### What the loop must look like

Lane lowering needs a whole-function shape it can reason about: one top-level
numeric `for` loop over spans, indexed by the loop counter exactly. Inside the
body it handles rather more than that — nested conditionals as mask stacks,
short-circuit `and`/`or` where both sides are pure and total, a data-dependent
inner `while`, and per-lane `break` and `continue`.

Where it cannot, the body still compiles: it keeps its scalar loop, and the
refusal names the construct that stopped it. A loop that does not vectorize is a
performance property, not a wrong answer, so it is not a build error.

### Influencing it

Three levers, and no more than three. None of them lets you name a lane.

**`@aot(lanes = true)`** takes lane lowering whatever the intensity estimate
says. Use it when you have measured the loop and the estimate disagrees with the
measurement. It does not require the lowering to succeed.

**`@aot(lanes = false)`** declines lane lowering for a body that would otherwise
be lowered. Use it for a loop that is deliberately scalar, so a vectorisation
check does not report it.

**`@relax("fp-contract")`** permits a multiply and an add to fuse into one
rounding. It is per function and travels with the IR rather than being a
build-wide flag, because it changes what the function answers and not only how
fast it gets there. On this kernel it is worth about 6%: 75.8 against 71.1
MPix/s lane-parallel, 36.9 against 35.0 forced scalar.
`bench/kernel-subset-spike/mandelbrot_exact.nupp` is the same source without it.

Removing `lanes = true` or `lanes = false` changes the compilation strategy and
never the answer. Removing `@relax` changes the answer.

**The fourth lever is the source itself**, and it is the strongest one. Writing
the arithmetic through `nupp.math.f32` doubles the lane count, because it tells
the backend the values are genuinely 32-bit rather than binary64 values that
happen to be small. That is a change to the program's meaning — different
roundings, different results — which is exactly why the compiler will not do it
for you.

### What you cannot do

There is no vector type, no mask value, no shuffle, and no way to name a width.
That is deliberate and it is written down in
[plans/037-portable-vectors.md](https://github.com/nupp-lang/nupp/blob/main/plans/037-portable-vectors.md):
an earlier design exposed `F32x8`, `I32x8` and mask values, and it was removed.
Scalar source already gets target-selected width, masks and divergent control
flow, exact scalar tails, one spelling that works with the backend off, and the
freedom to change gang shape later. An explicit vector type would mostly restate
a map loop while adding decisions about preferred versus fixed width, boxing
outside `@aot`, escape rules, and cross-target ABI.

The case for revisiting that is cross-lane meaning a scalar loop cannot express
— shuffles, transposes, prefix scans, fixed-tree reductions, gathers, compress
and expand — in several real kernels. A kernel that merely vectorizes imperfectly
is not the case.

## Numeric guarantees

| Written | Computed as | Notes |
| --- | --- | --- |
| `a + b` on numbers | binary64 | not contracted, not reassociated |
| a `float` field read | binary64 | the physical load widens |
| a `float` field write | binary32 | the physical store narrows |
| `nupp.math.f32.add(a, b)` | binary32, one rounding | exact, see below |
| `nupp.math.f32.min`/`max`/`fma` | binary32, corrected | a helper repairs NaN behaviour |
| `nupp.math.i32.add(a, b)` | wrapping int32 | wraps in unsigned, comes back |

The binary32 operations lower to native single-precision instructions and this
is exact rather than a relaxation: a binary32 operation over binary32 operands
computed in binary64 and rounded once is bit-identical to the native
instruction, because 53 ≥ 2 × 24 + 2.

`min`, `max` and `fma` are not covered by that argument. A differential over
every interesting binary32 value found they disagree with `fminf`, `fmaxf` and
`fmaf` in exactly one respect each: `nupp.math.f32` canonicalizes every NaN
where the instruction propagates a payload, and `min`/`max` return that
canonical NaN where IEEE `minNum` returns the operand that is not NaN. Both are
repaired by a select, so they are admitted with a correction rather than left
out.

A width changes only at a conversion the IR writes down. An operator never
changes one, which is what keeps `float` a storage fact rather than an
arithmetic type.

## How it is checked

Generated C is a backend representation and not the safety boundary. Every span
access, region relationship, conversion and lane operation is verified in the IR
before anything is emitted, so a rewrite that produced something invalid is a
compiler bug caught before it becomes a miscompilation.

Two rules do most of the work. Every load, store and element reference indexes
the loop counter and nothing else — that is both the argument that an access is
in bounds and the licence to run several iterations at once. And the alias
matrix is required complete rather than merely consistent: every pair of span
regions carries a fact, because a pair with no fact would be a `restrict` nobody
justified.

Above that sit the differentials, which is where correctness is actually
established. Ordinary Nupp, forced-scalar C and lane-parallel C are all built
from one source and must agree exactly — not within a tolerance, because the
arithmetic is specified to be the same work in the same order:

```bash
bench/kernel-subset-spike/simd.sh                     # lane rewrite vs scalar
luajit bench/kernel-subset-spike/corrected_main.lua   # binary32 min/max/fma
luajit bench/kernel-subset-spike/tecsbits_main.lua    # bitwise lanes over entities
luajit bench/kernel-subset-spike/mandelbrot_main.lua  # every pixel, three ways
```

Tails are exercised at every remainder for both gang widths, so a four-lane and
an eight-lane tail are both covered.

## Diagnostics

| Code | Meaning |
| --- | --- |
| NUPP2901 | `@aot` stacked with `@jit` — one body promised to two compilers |
| NUPP2902 | `@aot` on something that is not a whole function |
| NUPP2903 | A construct in an `@aot` body with no AOT IR form |

A closure, table, interpolated string, vararg, `goto`, dynamic call or unsafe
operation inside an `@aot` body reports NUPP2903 at the construct.

## See also

- [Optimization](optimization.md) — what the ordinary Lua backend does
- [LuaJIT trace checking](jit-trace-checking.md) — the same category of
  performance property, for the JIT rather than the AOT path
- [Effect contracts](../effects.md) — the purity `@aot` helpers rely on
- [Ownership](../ownership.md) — where the alias facts come from
